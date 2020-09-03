defmodule Elementary.Streams do
  @moduledoc false
  alias Elementary.{Index, Stores.Store, Streams.Workers}
  require Logger

  def set_capacity(stream, desired) do
    Workers.set_capacity(stream, desired)
  end

  def capacity(stream) do
    Workers.capacity(stream)
  end

  def write_async(stream, data) do
    spawn(fn ->
      write(stream, data)
    end)

    :ok
  end

  def write(stream, data) do
    %{"spec" => %{"settings" => %{"store" => store}}} = Index.spec!("stream", stream)
    data = stream_doc(data)

    case Store.insert(store, stream, data) do
      :ok ->
        true

      {:error, e} ->
        Logger.warn("Error while writing to stream #{stream}: #{inspect(e)}")
        %{"error" => "#{inspect(e)}"}
    end
  end

  defp stream_doc(data) when is_map(data) do
    data
    |> Map.drop(["id", "_id"])
  end

  defp stream_doc(data) when is_list(data) do
    Enum.map(data, &stream_doc(&1))
  end

  def info(stream) do
    %{"spec" => %{"settings" => %{"store" => store}}} = Index.spec!("stream", stream)

    %{
      "total" => Store.count(store, stream, %{}) |> stat(),
      "inflight" =>
        Store.count(store, stream, %{
          "started" => %{"$exists" => true},
          "finished" => %{"$exists" => false}
        })
        |> stat(),
      "backlog" =>
        Store.count(store, stream, %{
          "started" => %{"$exists" => false},
          "finished" => %{"$exists" => false}
        })
        |> stat()
    }
  end

  defp stat({:ok, stat}), do: stat
  defp stat({:error, e}), do: "#{inspect(e)}"

  use Supervisor
  alias Elementary.{Index, Streams.StreamSup}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    Index.specs("stream")
    |> Enum.map(&service_spec(&1))
    |> Supervisor.init(strategy: :one_for_one)
  end

  defp service_spec(spec) do
    %{
      id: StreamSup.name(spec),
      start: {StreamSup, :start_link, [spec]}
    }
  end

  defmodule StreamSup do
    use Supervisor
    alias Elementary.Streams.{Replay, Monitor, Workers, Worker, Scheduler}

    def name(%{"name" => name}), do: String.to_atom("#{name}_supervisor")

    def start_link(spec) do
      Supervisor.start_link(__MODULE__, spec, name: name(spec))
    end

    def init(spec) do
      [
        %{
          id: Monitor.name(spec),
          start: {Monitor, :start_link, [spec]}
        },
        %{
          id: Replay.name(spec),
          start: {Replay, :start_link, [spec]}
        },
        %{
          id: Workers.name(spec),
          start: {Workers, :start_link, [spec]}
        },
        %{
          id: Scheduler.name(spec),
          start: {Scheduler, :start_link, [spec]}
        }
      ]
      |> Supervisor.init(strategy: :one_for_one)
    end
  end

  defmodule Monitor do
    use GenServer
    alias Elementary.{Kit, Slack}

    def name(%{"name" => name}), do: name(name)
    def name(name), do: String.to_atom("#{name}_monitor")

    def start_link(spec) do
      GenServer.start_link(__MODULE__, spec, name: name(spec))
    end

    def register(name) do
      name
      |> name()
      |> GenServer.cast({:register, self()})
    end

    @impl true
    def init(%{"name" => name}) do
      {:ok, %{stream: name, host: Kit.hostname(), ref: nil}}
    end

    @impl true
    def handle_cast({:register, pid}, %{stream: stream, host: host} = state) do
      Process.monitor(pid)

      report_capacity(stream, host, "connected")

      {:noreply, state}
    end

    @impl true
    def handle_info(
          {:DOWN, _, :process, _, reason},
          %{stream: stream, host: host} = state
        ) do
      report_capacity(stream, host, reason)

      {:noreply, state}
    end

    defp report_capacity(stream, host, reason) do
      %{"spec" => spec} = Index.spec!("stream", stream)

      desired = spec["capacity"] || 1
      actual = Workers.capacity(stream)

      capacity =
        case desired do
          0 ->
            0

          _ ->
            trunc(100 * actual / desired)
        end

      severity =
        case capacity do
          0 ->
            "danger"

          100 ->
            "good"

          _ ->
            "warning"
        end

      Slack.notify_async(%{
        channel: "cluster",
        title:
          "Stream `#{stream}` has capacity *#{capacity}%* in `#{host}` with reason `#{
            inspect(reason)
          }`",
        severity: severity,
        doc: nil
      })
    end
  end

  defmodule Replay do
    use GenServer
    alias Elementary.{App, Kit, Slack, Stores.Store, Calendar, Streams}

    @poll_interval 5
    @inflight_timeout 60

    def start_link(spec) do
      GenServer.start_link(__MODULE__, spec, name: name(spec))
    end

    def name(%{"name" => name}), do: name(name)
    def name(name), do: String.to_atom("#{name}_replay")

    @impl true
    def init(%{"name" => name} = spec) do
      %{"store" => store} = App.settings!(spec)

      initial_state = %{
        stream: name,
        store: store,
        col: name,
        host: Kit.hostname()
      }

      schedule_next()

      {:ok, initial_state}
    end

    @impl true
    def handle_info(:replay, %{stream: stream, store: store, host: host} = state) do
      with {:ok, updated} when updated > 0 <- replay(state) do
        Slack.notify_async(%{
          channel: "cluster",
          title: "Host `#{host}` replayed *#{updated} job(s)* inflight in stream `#{stream}`",
          severity: "warning",
          doc: nil
        })
      end

      Store.ensure(
        store,
        "cluster",
        %{"stream" => stream},
        Map.merge(%{"ts" => "$$NOW"}, Streams.info(stream))
      )

      schedule_next()

      {:noreply, state}
    end

    @impl true
    def handle_call(:replay, _, state) do
      {:reply, replay(state), state}
    end

    defp schedule_next() do
      Process.send_after(self(), :replay, @poll_interval * 1000)
    end

    def replay(%{store: store, col: col}) do
      {:ok, replay_date} = Calendar.time_ago(@inflight_timeout, :second)

      where = %{
        "finished" => %{"$exists" => false},
        "started" => %{"$lt" => replay_date}
      }

      Store.update_many(
        store,
        col,
        where,
        %{"$unset" => %{"started" => "", "finished" => ""}}
      )
    end

    def replay(stream) do
      GenServer.call(name(stream), :replay)
    end
  end

  defmodule Workers do
    use DynamicSupervisor
    alias Elementary.{Kit, Streams.Worker}

    def name(%{"name" => name}), do: name(name)
    def name(name) when is_binary(name), do: String.to_atom("#{name}_workers")
    def name(name), do: name

    def size(stream) do
      stream
      |> name()
      |> Supervisor.count_children()
    end

    def capacity(stream) do
      stream
      |> name()
      |> Kit.alive_dynamic_workers()
      |> Enum.count()
    end

    def set_capacity(stream, desired) do
      stream = name(stream)

      case desired - capacity(stream) do
        0 ->
          :ok

        diff when diff > 0 ->
          scale_up(stream, diff)

        diff when diff < 0 ->
          scale_down(stream, -1 * diff)
      end

      capacity(stream)
    end

    def scale_up(stream, count) do
      stream = name(stream)

      1..count
      |> Enum.each(fn _ ->
        DynamicSupervisor.start_child(stream, Worker)
      end)
    end

    def scale_down(stream, count) do
      stream = name(stream)

      stream
      |> Kit.alive_dynamic_workers()
      |> Enum.take(count)
      |> Enum.each(fn pid ->
        DynamicSupervisor.terminate_child(stream, pid)
      end)
    end

    def start_link(spec) do
      DynamicSupervisor.start_link(__MODULE__, spec, name: name(spec))
    end

    def init(spec) do
      DynamicSupervisor.init(
        strategy: :one_for_one,
        extra_arguments: [spec]
      )
    end
  end

  defmodule Scheduler do
    use GenServer
    alias Elementary.{App, Kit, Stores.Store, Streams.Workers}

    def start_link(spec) do
      GenServer.start_link(__MODULE__, spec, name: name(spec))
    end

    def name(%{"name" => name}), do: name(name)
    def name(name), do: String.to_atom("#{name}_scheduler")

    @impl true
    def init(%{"name" => name, "spec" => inner} = spec) do
      capacity = inner["capacity"] || 1

      initial_state = %{
        stream: name,
        capacity: capacity,
        host: Kit.hostname()
      }

      %{"store" => store} = App.settings!(spec)

      :ok = Store.ensure_collection(store, name, [])
      :ok = Store.ensure_index(store, name, %{"lookup" => "started"})
      :ok = Store.ensure_index(store, name, %{"lookup" => "finished"})

      {:ok, initial_state, {:continue, :schedule}}
    end

    @impl true
    def handle_continue(:schedule, state) do
      schedule(state)

      {:noreply, state}
    end

    @impl true
    def handle_info(:schedule, state) do
      schedule(state)
      {:noreply, state}
    end

    defp schedule(%{stream: stream, capacity: capacity}) do
      Workers.set_capacity(stream, capacity)
      Process.send_after(self(), :schedule, 5000)
    end
  end

  defmodule Worker do
    use GenServer, restart: :transient
    alias Elementary.{Kit, App, Stores.Store, Services.Service, Streams, Streams.Monitor}
    require Logger

    def start_link(spec, _) do
      GenServer.start_link(__MODULE__, spec)
    end

    @impl true
    def init(%{"name" => name, "spec" => spec0} = spec) do
      %{"store" => store} = App.settings!(spec)

      alert =
        case spec0 do
          %{"alert" => alert} ->
            alert

          _ ->
            nil
        end

      apps =
        case spec0 do
          %{"apps" => apps} ->
            apps

          _ ->
            []
        end

      initial_state = %{
        stream: name,
        store: store,
        col: name,
        apps: apps,
        alert: alert,
        subscription: nil,
        offset: "",
        host: Kit.hostname()
      }

      schedule_next()

      Monitor.register(name)

      {:ok, initial_state}
      # {:continue, :subscribe}}
    end

    @poll_interval 1

    @impl true
    def handle_info(:poll, state) do
      with data when is_map(data) <- pop(state) do
        handle_data(data, state)
        ack(data, state)
      end

      schedule_next()

      {:noreply, state}
    end

    @impl true
    def handle_info(other, state) do
      Logger.warn("unexpected info message #{inspect(other)} in #{inspect(state)}")
      {:noreply, state}
    end

    def stop(reason, %{stream: stream} = state) do
      Logger.warn("stopped stream #{stream} (#{inspect(self())}): #{reason}")
      {:ok, state}
    end

    defp error_as_map(map) when is_map(map), do: map

    defp error_as_map(other) do
      %{"error" => other}
    end

    defp schedule_next() do
      Process.send_after(self(), :poll, @poll_interval * 1000)
    end

    defp pop(%{store: store, col: col}) do
      case Store.find_one_and_update(
             store,
             col,
             %{"started" => %{"$exists" => false}},
             %{"started" => "$$NOW"},
             sort: %{"id" => "desc"}
           ) do
        {:ok, data} ->
          data

        {:error, :not_found} ->
          nil
      end
    end

    defp handle_data(%{"id" => id} = data, %{apps: apps} = state) do
      data =
        data
        |> Map.put("ts", Kit.datetime_from_mongo_id(id))
        |> Map.drop(["started"])

      maybe_alert(data, state, state)

      :ok =
        Enum.each(apps, fn app ->
          with {:error, e} <- Service.run(app, "caller", data) do
            error =
              e |> error_as_map() |> Map.merge(%{"app" => app, "timestamp" => DateTime.utc_now()})

            Streams.write_async("errors", error)
          end
        end)
    end

    defp ack(%{"id" => id}, %{store: store, col: col}) do
      Store.update(store, col, %{"id" => id}, %{"finished" => "$$NOW"})
    end

    defp maybe_alert(_, %{alert: nil}, _), do: false

    defp maybe_alert(data, %{alert: %{"channel" => channel, "title" => title} = spec}, %{
           host: host
         }) do
      with data <- Map.merge(%{"host" => host}, data),
           {:ok, title} <- Elementary.Encoder.encode(%{"format" => title, "params" => data}, data) do
        doc =
          case spec["doc"] do
            true ->
              data

            _ ->
              nil
          end

        sev =
          case Elementary.Encoder.encode(spec["severity"] || "@severity", data) do
            {:ok, sev} ->
              sev

            _ ->
              "default"
          end

        Elementary.Slack.notify_async(%{
          channel: channel,
          severity: sev,
          title: title,
          doc: doc
        })

        true
      end
    end
  end
end
