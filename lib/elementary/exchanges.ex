defmodule Elementary.Exchanges do
  @moduledoc """
  A gateway to a crypto exchange
  """

  use Supervisor
  alias Elementary.Exchanges.Fake

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  def init(_) do
    [Fake]
    |> Supervisor.init(strategy: :one_for_one)
  end

  defmodule Fake do
    @moduledoc false

    use GenServer
    alias Elementary.Stores.Store
    alias Elementary.Index
    alias Elementary.Channels.Channel
    require Logger

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    def init(_) do
      Index.specs("symbol")
      |> Enum.map(fn %{"name" => name} ->
        Channel.subscribe(name)
      end)

      last_id =
        case Store.find_all(:default, :orders, %{}, limit: 1, sort: [order_id: :desc]) do
          {:ok, []} ->
            0

          {:ok, [%{"order_id" => last_id}]} ->
            last_id
        end

      {:ok, %{last_order_id: last_id}}
    end

    def buy(order) do
      GenServer.call(__MODULE__, {:buy, order})
    end

    def order(symbol, timestamp, order_id) do
      GenServer.call(__MODULE__, {:get, symbol, timestamp, order_id})
    end

    def handle_info(_info, state) do
      {:noreply, state}
    end

    def handle_call({:buy, %{symbol: s, q: q, p: p}}, _, state) do
      current_timestamp = :os.system_time(:millisecond)
      {order_id, state} = new_order_id(state)
      client_order_id = :crypto.hash(:md5, "#{order_id}") |> Base.encode16()

      order = %{
        symbol: s,
        order_id: order_id,
        client_order_id: client_order_id,
        price: Float.to_string(p),
        orig_qty: Float.to_string(q),
        executed_qty: "0.00000000",
        cummulative_quote_qty: "0.00000000",
        status: "NEW",
        time_in_force: "GTC",
        type: "LIMIT",
        side: "BUY",
        stop_price: "0.00000000",
        iceberg_qty: "0.00000000",
        time: current_timestamp,
        update_time: current_timestamp,
        is_working: true
      }

      :ok = Store.insert(:default, :orders, order)
      {:reply, {:ok, order}, state}
    end

    def handle_call({:get, symbol, timestamp, order_id}, _, state) do
      Logger.info("get #{symbol}, #{timestamp}, #{order_id}")
      {:reply, {:ok, %{"order_id" => %{}}}, state}
    end

    defp new_order_id(%{last_order_id: last} = state) do
      last = last + 1
      {last, %{state | last_order_id: last}}
    end
  end
end
