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
    use GenServer
    alias Elementary.Stores.Store
    alias Elementary.Channels.Channel
    alias Elementary.Kit
    alias Elementary.Index

    require Logger

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    def buy(s, q, p) do
      GenServer.call(__MODULE__, {:buy, s, q, p})
    end

    def sell(s, q, p) do
      GenServer.call(__MODULE__, {:sell, s, q, p})
    end

    def find_order(_symbol, _timestamp, order_id) do
      Store.find_one(:default, :fake_orders, %{
        order_id: order_id
      })
    end

    def init(_) do
      {:ok, orders} =
        Store.find_all(:default, :fake_orders, %{
          "status" => "NEW"
        })

      Logger.info("Loaded #{length(orders)} pending orders")

      Index.specs("symbol")
      |> Enum.each(fn %{"name" => s} ->
        :ok = Channel.subscribe(s)
      end)

      {:ok, %{orders: orders, last_order_id: last_order_id()}}
    end

    def handle_call({:buy, s, q, p}, _, state) do
      {order, state} = new_order("BUY", s, q, p, state)

      :ok = Store.insert(:default, :fake_orders, order)
      Logger.info("[new] [BUY] [#{order["order_id"]}]: #{q} #{s} @ #{p}")
      {:reply, {:ok, order}, state}
    end

    def handle_call({:sell, s, q, p}, _, state) do
      {order, state} = new_order("SELL", s, q, p, state)

      :ok = Store.insert(:default, :fake_orders, order)
      Logger.info("[new] [SELL] [#{order["order_id"]}]: #{q} #{s} @ #{p}")

      {:reply, {:ok, order}, state}
    end

    def handle_info(
          %{"event" => "trade", "p" => p, "s" => s},
          %{orders: orders} = state
        ) do
      p = Kit.float_from(p)

      orders =
        Enum.reduce(orders, [], fn order, acc ->
          case maybe_fill_order(s, p, order) do
            true ->
              acc

            false ->
              [order | acc]
          end
        end)

      {:noreply, %{state | orders: orders}}
    end

    def handle_info(_, state), do: {:noreply, state}

    defp last_order_id do
      case Store.find_all(:default, :fake_orders, %{}, limit: 1, sort: [order_id: :desc]) do
        {:ok, []} ->
          0

        {:ok, [%{"order_id" => last_id}]} ->
          last_id
      end
    end

    defp new_order(side, symbol, q, p, %{last_order_id: order_id, orders: orders} = state) do
      order_id = order_id + 1
      current_timestamp = :os.system_time(:millisecond)
      client_order_id = :crypto.hash(:md5, "#{order_id}") |> Base.encode16()

      order = %{
        "symbol" => symbol,
        "order_id" => order_id,
        "client_order_id" => client_order_id,
        "price" => p,
        "orig_qty" => q,
        "executed_qty" => "0.00000000",
        "cummulative_quote_qty" => "0.00000000",
        "status" => "NEW",
        "time_in_force" => "GTC",
        "type" => "LIMIT",
        "side" => side,
        "stop_price" => "0.00000000",
        "iceberg_qty" => "0.00000000",
        "time" => current_timestamp,
        "update_time" => current_timestamp,
        "is_working" => true
      }

      orders = [order | orders]

      {order, %{state | orders: orders, last_order_id: order_id}}
    end

    def maybe_fill_order(
          s,
          trade_price,
          %{
            "order_id" => order_id,
            "symbol" => s,
            "orig_qty" => q,
            "side" => side,
            "price" => order_price
          }
        ) do
      with true <- should_fill_order(trade_price, side, order_price),
           true <- update_filled_order(order_id) do
        trade_event = %{
          "event" => "trade",
          "s" => s,
          "p" => Float.to_string(order_price),
          "buyer_order_id" => order_id,
          "seller_order_id" => order_id
        }

        :ok = Channel.publish(s, trade_event)
        Logger.info("[filled] [#{side}] [#{order_id}]: #{q} #{s} @ #{order_price}")

        true
      else
        _ ->
          false
      end
    end

    def maybe_fill_order(_, _, _), do: false

    def should_fill_order(trade_price, "BUY", order_price), do: trade_price < order_price
    def should_fill_order(trade_price, "SELL", order_price), do: trade_price > order_price

    def update_filled_order(order_id) do
      case Store.update(:default, :fake_orders, %{order_id: order_id, status: "NEW"}, %{
             status: "FILLED"
           }) do
        {:ok, 1} ->
          true

        {:ok, 0} ->
          Logger.warn("Could not fill order #{order_id}")
          false
      end
    end
  end
end
