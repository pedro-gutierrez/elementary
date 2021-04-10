defmodule Elementary.Cluster do
  @moduledoc false
  use Supervisor
  alias Elementary.{Kit, Index, Stores.Store}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def info() do
    %{"spec" => %{"store" => store}} = Elementary.Index.spec!("cluster", "default")

    with {:ok, items} <-
           Store.find_all(store, "cluster", %{}) do
      Enum.reduce(items, %{"hosts" => %{}, "streams" => %{}}, &cluster_info(&1, &2))
    end
  end

  def cluster_info(
        %{
          "host" => name
        } = item,
        %{"hosts" => hosts} = acc
      ) do
    host =
      item
      |> Map.take(["memory", "version"])

    hosts = Map.put(hosts, name, host)

    Map.put(acc, "hosts", hosts)
  end

  def cluster_info(
        %{"stream" => name} = item,
        %{"streams" => streams} = acc
      ) do
    stream =
      item
      |> Map.take(["backlog", "inflight", "total"])

    streams = Map.put(streams, name, stream)

    Map.put(acc, "streams", streams)
  end

  def init(_) do
    [{Elementary.Cluster.Info, Index.spec!("cluster", "default")}]
    |> Supervisor.init(strategy: :one_for_one)
  end

  defmodule Info do
    use GenServer

    def start_link(spec) do
      GenServer.start_link(__MODULE__, spec, name: __MODULE__)
    end

    @impl true
    def init(%{
          "spec" => %{
            "refresh" => refresh,
            "store" => store
          }
        }) do
      state =
        %{
          host: Kit.hostname(),
          store: store,
          refresh: refresh,
          version: Kit.version()
        }
        |> schedule_next()

      {:ok, state}
    end

    @impl true
    def handle_info(:report, state) do
      state =
        state
        |> report()
        |> schedule_next()

      {:noreply, state}
    end

    defp report(%{store: store, host: host, version: version} = state) do
      store = Index.spec!("store", store)

      %{total: memory} = Elementary.Kit.memory()

      Store.ensure(store, "cluster", %{"host" => host}, %{
        "ts" => "$$NOW",
        "memory" => memory,
        "version" => version
      })

      state
    end

    defp schedule_next(%{refresh: refresh} = state) do
      Process.send_after(self(), :report, refresh * 1000)
      state
    end
  end
end
