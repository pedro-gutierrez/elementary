defmodule Elementary.Streams do
  @moduledoc false

  use Supervisor
  alias Elementary.{Index, Streams.Stream, Slack}

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
      id: Stream.name(spec),
      start: {Elementary.Streams.StreamSupervisor, :start_link, [spec]}
    }
  end

  defmodule StreamSupervisor do
    use Supervisor
    alias Elementary.{App, Index, Stores, Stores.Store, Streams.Stream}

    def name(%{"name" => name}) do
      String.to_atom("#{name}_supervisor")
    end

    def start_link(spec) do
      Supervisor.start_link(__MODULE__, spec, name: name(spec))
    end

    def init(%{"name" => name} = spec) do
      %{"store" => store} = App.settings!(spec)

      store_spec =
        "store"
        |> Index.spec!(store)
        |> Map.put("name", name)

      [
        %{
          id: Stream.name(spec),
          start: {Stream, :start_link, [spec]}
        },
        Stores.store_spec(store_spec)
      ]
      |> Supervisor.init(strategy: :one_for_one)
    end
  end

  defmodule Stream do
    use GenServer
    alias Elementary.{Kit, Index, Stores.Store, Services.Service, Cluster}
    require Logger

    def start_link(spec) do
      GenServer.start_link(__MODULE__, spec, name: name(spec))
    end

    def name(%{"name" => name}), do: String.to_atom("#{name}_stream")

    def write(stream, data) do
      %{"spec" => %{"size" => size}} = Index.spec!("cluster", "default")

      partition = :rand.uniform(size) - 1

      col = stream

      data = stream_doc_from_data(partition, data)

      case Store.insert(stream, col, data) do
        :ok ->
          true

        _ ->
          false
      end
    end

    defp stream_doc_from_data(partition, data) when is_map(data) do
      data
      |> Map.put("p", partition)
      |> Map.drop(["id", "_id"])
    end

    defp stream_doc_from_data(partition, data) when is_list(data) do
      Enum.map(data, &stream_doc_from_data(partition, &1))
    end

    def write_async(stream, data) do
      spawn(fn ->
        write(stream, data)
      end)

      :ok
    end

    @impl true
    def init(%{"name" => name, "spec" => spec0} = spec) do
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
        store: name,
        col: name,
        apps: apps,
        alert: alert,
        subscription: nil,
        offset: "",
        partition: cluster.partition,
        cluster_size: cluster.size,
        host: Kit.hostname()
      }

      {:ok, initial_state, {:continue, :subscribe}}
    end

    @impl true
    def handle_continue(
          :subscribe,
          %{
            registered: registered,
            store: store,
            stream: stream,
            col: col,
            partition: partition,
            host: host
          } = state
        ) do
      case read_offset(state) do
        {:error, e} ->
          Logger.warn("Error #{inspect(e)} from stream #{stream} while reading offset")
          {:stop, :error_subscribing, state}

        {:ok, offset} ->
          data_fn = fn data ->
            GenServer.cast(registered, data)
          end

          {:ok, pid} = Store.subscribe(store, col, partition, %{"offset" => offset}, data_fn)

          IO.inspect(
            stream: stream,
            store: store,
            collection: col,
            partition: partition,
            status: :subscribed,
            offset: offset
          )

          Slack.notify(%{
            channel: "cluster",
            title: "Host `#{host}` subscribed to `partition #{partition}` of stream `#{stream}`",
            severity: "good",
            doc: nil
          })

          {:noreply, %{state | offset: offset, subscription: pid}}
      end
    end

    @impl true
    def handle_info(other, state) do
      Logger.warn("unexpected info message #{inspect(other)} in #{inspect(state)}")
      {:noreply, state}
    end

    @impl true
    def handle_cast(%{"offset" => offset}, state) do
      state = %{state | offset: offset}
      :ok = write_offset(state)
      {:noreply, state}
    end

    @impl true
    def handle_cast(%{"data" => %{"id" => id} = data}, %{apps: apps} = state) do
      data =
        data
        |> Map.put("ts", Kit.datetime_from_mongo_id(id))

      maybe_alert(data, state, state)

      :ok =
        Enum.each(apps, fn app ->
          with {:error, e} <- Service.run(app, "caller", data) do
            error =
              e |> error_as_map() |> Map.merge(%{"app" => app, "timestamp" => DateTime.utc_now()})

            Stream.write_async("errors", error)
            # store = Index.spec!("store", store)
            # Store.insert(store, "errors", error)
          end
        end)

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

    defp read_offset(%{stream: stream, id: id}) do
      case Store.find_one(stream, "streams", %{"id" => id}) do
        {:ok, %{"offset" => offset}} ->
          {:ok, offset}

        {:error, :not_found} ->
          {:ok, ""}

        other ->
          other
      end
    end

    defp write_offset(%{stream: stream, id: id, host: host, offset: offset}) do
      case Store.ensure(stream, "streams", %{"id" => id}, %{
             "offset" => offset,
             "ts" => "$$NOW",
             "host" => host
           }) do
        {:ok, _} ->
          :ok

        {:error, e} ->
          Logger.error("Error updating offset \"#{offset}\" for stream \"#{id}\": #{inspect(e)}")

          :ok
      end
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
