defmodule Elementary.Cluster do
  @moduledoc false

  use Supervisor
  alias Elementary.{Kit, Index, Stores.Store}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    [{__MODULE__.Info, Index.spec!("cluster", "default")}]
    |> Supervisor.init(strategy: :one_for_one)
  end

  def info() do
    GenServer.call(__MODULE__.Info, :info)
  end

  defmodule Info do
    use GenServer

    def start_link(spec) do
      GenServer.start_link(__MODULE__, spec, name: __MODULE__)
    end

    def partition(%{"spec" => %{"prefix" => prefix}}) do
      Elementary.Kit.hostname()
      |> String.replace_prefix(prefix, "")
      |> String.to_integer()
    end

    @impl true
    def init(
          %{
            "spec" => %{
              "refresh" => refresh,
              "store" => store,
              "size" => size
            }
          } = spec
        ) do
      partition =
        case size do
          1 ->
            0

          size when size > 1 ->
            partition(spec)
        end

      state = %{
        host: Kit.hostname(),
        store: store,
        refresh: refresh,
        size: size,
        partition: partition
      }

      :ok = report(state)

      {:ok, state}
    end

    @impl true
    def handle_info(:report, state) do
      :ok = report(state)
      {:noreply, state}
    end

    @impl true
    def handle_call(:info, _, state) do
      {:reply, {:ok, Map.take(state, [:size, :partition])}, state}
    end

    defp report(%{store: store, host: host, refresh: refresh, partition: partition, size: size}) do
      store = Index.spec!("store", store)

      Store.ensure(store, "cluster", %{"host" => host}, %{
        "size" => size,
        "p" => partition,
        "ts" => "$$NOW"
      })

      Process.send_after(self(), :report, refresh * 1000)
      :ok
    end
  end
end
