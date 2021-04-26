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
    use Supervisor
    alias Elementary.Exchanges.Fake.Leader
    alias Elementary.Exchanges.Fake.Orders
    alias Elementary.Stores.Store

    def start_link(opts) do
      Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    end

    def init(_) do
      [Orders, Leader]
      |> Supervisor.init(strategy: :rest_for_one)
    end

    def buy(s, q, p) do
      GenServer.call(Leader, {:buy, s, q, p})
    end

    def find_order(_symbol, _timestamp, order_id) do
      Store.find_one(:default, :orders, %{
        order_id: order_id
      })
    end

    defmodule Orders do
      @moduledoc """
      A fake Binance exchange simulator
      """

      use DynamicSupervisor
      alias Elementary.Exchanges.Fake.Order

      def start_link(opts) do
        DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
      end

      def init(_) do
        DynamicSupervisor.init(
          strategy: :one_for_one,
          extra_arguments: []
        )
      end

      def start_new(order) do
        DynamicSupervisor.start_child(__MODULE__, {Order, order})
      end
    end

    defmodule Leader do
      @moduledoc """
      Loads existing non filled orders during startup
      """

      use GenServer
      alias Elementary.Exchanges.Fake.Orders
      alias Elementary.Stores.Store

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      def init(_) do
        last_id =
          case Store.find_all(:default, :orders, %{}, limit: 1, sort: [order_id: :desc]) do
            {:ok, []} ->
              0

            {:ok, [%{"order_id" => last_id}]} ->
              last_id
          end

        {:ok, %{last_order_id: last_id}, {:continue, :resume}}
      end

      def handle_continue(:resume, state) do
        {:ok, orders} =
          Store.find_all(:default, :orders, %{
            "status" => "NEW"
          })

        Enum.each(orders, fn order ->
          {:ok, _} = Orders.start_new(order)
        end)

        {:noreply, state}
      end

      def handle_call({:buy, s, q, p}, _, state) do
        {order, state} = new_order("BUY", s, q, p, state)

        :ok = Store.insert(:default, :orders, order)
        {:ok, _} = Orders.start_new(order)

        {:reply, {:ok, order}, state}
      end

      defp new_order(side, symbol, q, p, %{last_order_id: order_id} = state) do
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

        {order, %{state | last_order_id: order_id}}
      end
    end

    defmodule Order do
      @moduledoc """
      A fake order
      """

      use GenServer
      alias Elementary.Channels.Channel
      alias Elementary.Stores.Store
      alias Elementary.Kit
      require Logger

      def start_link(order) do
        GenServer.start_link(__MODULE__, order)
      end

      def init(%{"symbol" => s} = order) do
        Channel.subscribe(s)
        Logger.info("started order #{order["order_id"]}")
        {:ok, %{order: order}}
      end

      def handle_info(
            %{"event" => "trade", "p" => event_price},
            %{
              order:
                %{"symbol" => s, "side" => side, "price" => p, "order_id" => order_id} = order
            } = state
          ) do
        event_price = Kit.float_from(event_price)

        case should_fill_order(event_price, side, p) do
          true ->
            case Store.update(:default, :orders, %{order_id: order_id, status: "NEW"}, %{
                   status: "FILLED"
                 }) do
              {:ok, 1} ->
                Channel.publish(s, %{
                  "event" => "trade",
                  "s" => s,
                  "p" => Float.to_string(p),
                  "buyer_order_id" => order_id,
                  "seller_order_id" => order_id
                })

                Logger.info("order filled #{inspect(order)}")
                {:stop, :normal}

              {:ok, 0} ->
                # TODO figure out this strange condition
                {:stop, :normal}
            end

          false ->
            {:noreply, state}
        end

        {:noreply, state}
      end

      def handle_info(_, state), do: {:noreply, state}

      def should_fill_order(trade_price, "BUY", order_price), do: trade_price < order_price
      def should_fill_order(trade_price, "SELL", order_price), do: trade_price > order_price
    end
  end
end
