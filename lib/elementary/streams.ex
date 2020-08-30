defmodule Elementary.Streams do
  @moduledoc false

  use Supervisor
  alias Elementary.{Index, Streams.Stream, Streams.StreamSupervisor}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def info() do
    "stream"
    |> Index.specs()
    |> Enum.map(&Elementary.Streams.Stream.info(&1))
    |> Enum.reduce(%{}, fn %{"name" => name} = info, acc ->
      Map.put(acc, name, Map.drop(info, ["name"]))
    end)
  end

  def init(_) do
    Index.specs("stream")
    |> Enum.map(&service_spec(&1))
    |> Supervisor.init(strategy: :one_for_one)
  end

  defp service_spec(spec) do
    %{
      id: StreamSupervisor.name(spec),
      start: {StreamSupervisor, :start_link, [spec]}
    }
  end

  defmodule StreamSupervisor do
    use Supervisor
    alias Elementary.Streams.{Stream, Replay, Monitor}

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
          id: Stream.name(spec),
          start: {Stream, :start_link, [spec]}
        },
        %{
          id: Replay.name(spec),
          start: {Replay, :start_link, [spec]}
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
      |> GenServer.call({:register, self()})
    end

    @impl true
    def init(%{"name" => name}) do
      {:ok, %{stream: name, host: Kit.hostname(), ref: nil}}
    end

    @impl true
    def handle_call({:register, pid}, _, %{stream: stream, host: host} = state) do
      ref = Process.monitor(pid)

      Slack.notify_async(%{
        channel: "cluster",
        title: "Stream `#{stream}` is now connected in host `#{host}`",
        severity: "good",
        doc: nil
      })

      {:reply, :ok, %{state | ref: ref}}
    end

    @impl true
    def handle_info(
          {:DOWN, ref, :process, _, reason},
          %{stream: stream, host: host, ref: ref} = state
        ) do
      Slack.notify_async(%{
        channel: "cluster",
        title:
          "Stream `#{stream}` losts its connection from host `#{host}` with reason `#{
            inspect(reason)
          }`",
        severity: "danger",
        doc: nil
      })

      {:noreply, state}
    end
  end

  defmodule Replay do
    use GenServer
    alias Elementary.{App, Kit, Slack, Stores.Store, Calendar}

    @poll_interval 1
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
    def handle_info(:replay, %{stream: stream, host: host} = state) do
      with {:ok, updated} when updated > 0 <- replay(state) do
        Slack.notify_async(%{
          channel: "cluster",
          title: "Host `#{host}` replayed `#{updated} jobs` inflight in stream `#{stream}`",
          severity: "warning",
          doc: nil
        })
      end

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

  defmodule Stream do
    use GenServer
    alias Elementary.{Kit, App, Index, Stores.Store, Services.Service, Cluster, Streams.Monitor}
    require Logger

    def start_link(spec) do
      GenServer.start_link(__MODULE__, spec, name: name(spec))
    end

    def info(%{"name" => name}) do
      total = total(name)
      backlog = backlog(name)
      inflight = inflight(name)

      %{"name" => name, "backlog" => backlog, "inflight" => inflight, "total" => total}
    end

    def name(%{"name" => name}), do: String.to_atom("#{name}_poller")

    def write(stream, data) do
      %{"spec" => %{"settings" => %{"store" => store}}} = Index.spec!("stream", stream)
      data = stream_doc(data)

      case Store.insert(store, stream, data) do
        :ok ->
          true

        _ ->
          false
      end
    end

    def total(stream) do
      %{"spec" => %{"settings" => %{"store" => store}}} = Index.spec!("stream", stream)

      Store.count(store, stream, %{})
      |> stat()
    end

    def backlog(stream) do
      %{"spec" => %{"settings" => %{"store" => store}}} = Index.spec!("stream", stream)

      Store.count(store, stream, %{
        "started" => %{"$exists" => false},
        "finished" => %{"$exists" => false}
      })
      |> stat()
    end

    def inflight(stream) do
      %{"spec" => %{"settings" => %{"store" => store}}} = Index.spec!("stream", stream)

      Store.count(store, stream, %{
        "started" => %{"$exists" => true},
        "finished" => %{"$exists" => false}
      })
      |> stat()
    end

    defp stat({:ok, stat}), do: stat
    defp stat({:error, e}), do: "#{inspect(e)}"

    defp stream_doc(data) when is_map(data) do
      data
      |> Map.drop(["id", "_id"])
    end

    defp stream_doc(data) when is_list(data) do
      Enum.map(data, &stream_doc(&1))
    end

    def write_async(stream, data) do
      spawn(fn ->
        write(stream, data)
      end)

      :ok
    end

    @impl true
    def init(%{"name" => name, "spec" => spec0} = spec) do
      %{"store" => store} = App.settings!(spec)

      {:ok, cluster} = Cluster.info()

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
        registered: name(spec),
        stream: name,
        id: "#{name}-#{cluster.partition}",
        store: store,
        col: name,
        apps: apps,
        alert: alert,
        subscription: nil,
        offset: "",
        partition: cluster.partition,
        cluster_size: cluster.size,
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

            Stream.write_async("errors", error)
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
