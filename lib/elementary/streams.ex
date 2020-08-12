defmodule Elementary.Streams do
  @moduledoc false

  use Supervisor
  alias Elementary.{Index, Streams.Stream}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    Index.specs("stream")
    |> Enum.map(&service_spec(&1))
    |> Supervisor.init(strategy: :one_for_one)
  end

  defp service_spec(spec) do
    {Elementary.Streams.Stream, spec}
  end

  defmodule Stream do
    use GenServer
    alias Elementary.{Kit, Index, App, Stores.Store, Services.Service, Cluster}
    require Logger

    def start_link(spec) do
      GenServer.start_link(__MODULE__, spec, name: __MODULE__)
    end

    def write(stream, data) do
      %{"spec" => %{"size" => size}} = Index.spec!("cluster", "default")

      {:ok, size} = Elementary.Encoder.encode(size)
      size = String.to_integer(size)

      %{"spec" => %{"settings" => %{"store" => store}, "collection" => col}} =
        Index.spec!("stream", stream)

      partition = :rand.uniform(size)

      data =
        Map.merge(data, %{
          "id" => UUID.uuid4(),
          "p" => partition,
          "ts" => DateTime.utc_now()
        })

      case "store" |> Index.spec!(store) |> Store.insert(col, data) do
        :ok ->
          true

        _ ->
          false
      end
    end

    @impl true
    def init(%{"name" => name, "spec" => %{"apps" => apps, "collection" => col}} = spec) do
      %{"store" => store} = App.settings!(spec)

      {:ok, cluster} = Cluster.info()

      initial_state =
        %{
          stream: name,
          id: "#{name}-#{cluster.partition}",
          store: store,
          col: col,
          apps: apps,
          subscription: nil,
          offset: "",
          partition: cluster.partition,
          cluster_size: cluster.size,
          host: Kit.hostname()
        }
        |> IO.inspect()

      {:ok, initial_state, {:continue, :subscribe}}
    end

    @impl true
    def handle_continue(
          :subscribe,
          %{
            store: store,
            stream: stream,
            col: col,
            partition: partition
          } = state
        ) do
      offset = read_offset(state)

      data_fn = fn data ->
        GenServer.cast(__MODULE__, data)
      end

      {:ok, pid} = Store.subscribe(store, col, partition, %{"offset" => offset}, data_fn)

      IO.inspect(stream: stream, status: :subscribed, partition: partition)
      {:noreply, %{state | offset: offset, subscription: pid}}
    end

    @impl true
    def handle_info(other, state) do
      Logger.warn("unexpected info message #{inspect(other)} in #{inspect(state)}")
      {:noreply, state}
    end

    @impl true
    def handle_cast(%{"offset" => offset}, state) do
      {:noreply, %{state | offset: offset}}
    end

    @impl true
    def handle_cast(%{"data" => data}, %{store: store, apps: apps} = state) do
      IO.inspect(stream: data)

      :ok =
        Enum.each(apps, fn app ->
          with {:error, e} <- Service.run(app, "caller", data) do
            error = Map.merge(e, %{"app" => app, "timestamp" => DateTime.utc_now()})
            store = Index.spec!("store", store)
            Store.insert(store, "errors", error, logs: :disable)
          end
        end)

      :ok = write_offset(state)
      {:noreply, state}
    end

    def stop(reason, %{stream: stream} = state) do
      Logger.warn("stopped stream #{stream} (#{inspect(self())}): #{reason}")
      {:ok, state}
    end

    defp read_offset(%{store: store, id: id}) do
      case "store"
           |> Index.spec!(store)
           |> Store.find_one("streams", %{"id" => id}) do
        {:ok, %{"offset" => offset}} ->
          offset

        {:error, :not_found} ->
          ""
      end
    end

    defp write_offset(%{store: store, id: id, host: host, offset: offset}) do
      store = Index.spec!("store", store)

      case Store.ensure(store, "streams", %{"id" => id}, %{
             "offset" => offset,
             "tick" => DateTime.utc_now(),
             "host" => host
           }) do
        {:ok, 1} ->
          :ok

        {:error, e} ->
          Logger.error("Error updating offset: #{inspect(e)}")
          :ok
      end
    end

    # defp stream_info(%{stream: stream}) do
    #  %{name: stream, node: Node.self()}
    # end
  end
end
