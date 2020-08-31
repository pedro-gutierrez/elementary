defmodule Elementary.Cluster do
  @moduledoc false

  use Supervisor
  alias Elementary.{Kit, Index, Stores.Store, Calendar}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def info() do
    %{"spec" => %{"store" => store}} = Elementary.Index.spec!("cluster", "default")

    with {:ok, items} <-
           Store.aggregate(store, "cluster", [%{"$addFields" => %{"now" => "$$NOW"}}]) do
      Enum.reduce(items, %{"hosts" => %{}, "streams" => %{}}, &cluster_info(&1, &2))
    end
  end

  def cluster_info(
        %{
          "host" => name,
          "ts" => ts,
          "now" => now
        } = item,
        %{"hosts" => hosts} = acc
      ) do
    host =
      item
      |> Map.take(["memory"])
      |> Map.put("lastSeen", Calendar.duration_between(now, ts))

    hosts = Map.put(hosts, name, host)

    Map.put(acc, "hosts", hosts)
  end

  def cluster_info(
        %{"stream" => name, "ts" => ts, "now" => now} = item,
        %{"streams" => streams} = acc
      ) do
    stream =
      item
      |> Map.take(["backlog", "inflight", "total"])
      |> Map.put("lastSeen", Calendar.duration_between(now, ts))

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
            "store" => store,
            "size" => size
          }
        }) do
      state =
        %{
          host: Kit.hostname(),
          store: store,
          refresh: refresh,
          size: size
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

    defp report(%{store: store, host: host} = state) do
      store = Index.spec!("store", store)

      %{total: memory} = Elementary.Kit.memory()

      Store.ensure(store, "cluster", %{"host" => host}, %{
        "ts" => "$$NOW",
        "memory" => memory
      })

      state
    end

    defp schedule_next(%{refresh: refresh} = state) do
      Process.send_after(self(), :report, refresh * 1000)
      state
    end
  end
end
