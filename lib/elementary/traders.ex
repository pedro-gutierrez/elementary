defmodule Elementary.Traders do
  @moduledoc """
  A context for all traders
  """

  use Supervisor
  alias Elementary.Index
  alias Elementary.Traders.Trader

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    Index.specs("symbol")
    |> Enum.map(&Trader.child_spec(&1))
    |> Supervisor.init(strategy: :one_for_one)
  end

  defmodule Trader do
    @moduledoc """
    A trader on a specific symbol
    """
    use Supervisor
    alias Elementary.Traders.Leader
    alias Elementary.Traders.Trades

    def start_link(%{"name" => name} = spec) do
      name = String.to_atom("#{name}_trader")
      Supervisor.start_link(__MODULE__, spec, name: name)
    end

    def child_spec(%{"name" => name} = spec) do
      %{
        id: name,
        start: {__MODULE__, :start_link, [spec]}
      }
    end

    def init(spec) do
      [{Leader, spec}, {Trades, spec}]
      |> Supervisor.init(strategy: :one_for_one)
    end
  end

  defmodule Leader do
    @moduledoc """
    A trader on a specific symbol
    """
    @max_trades 1

    use GenServer
    alias Elementary.Channels.Channel
    alias Elementary.Kit
    alias Elementary.Traders.Trades

    def start_link(spec) do
      GenServer.start_link(__MODULE__, spec)
    end

    def init(%{"name" => name}) do
      Channel.subscribe(name)
      {:ok, %{buy: nil, sell: nil, symbol: name, count: 0}}
    end

    def handle_info(%{"event" => "trade"}, %{count: @max_trades} = state) do
      {:noreply, state}
    end

    def handle_info(%{"event" => "trade", "p" => p, "s" => s}, %{count: count} = state) do
      p = Kit.float_from(p)
      q = Kit.float_from("10.0")

      {:ok, _} = Trades.buy(s, q, p)
      {:noreply, %{state | count: count + 1}}
    end

    def handle_info(_, state), do: {:noreply, state}
  end

  defmodule Trades do
    @moduledoc """
    A dynamic supervisor for trades
    """
    use DynamicSupervisor
    alias Elementary.Traders.BuySell

    def start_link(%{"name" => name} = spec) do
      name = String.to_atom("#{name}_trades")
      DynamicSupervisor.start_link(__MODULE__, spec, name: name)
    end

    def init(spec) do
      DynamicSupervisor.init(
        strategy: :one_for_one,
        extra_arguments: [spec]
      )
    end

    def buy(s, q, p) do
      name = String.to_existing_atom("#{s}_trades")
      DynamicSupervisor.start_child(name, {BuySell, [q, p]})
    end
  end

  defmodule BuySell do
    @moduledoc """
    A trade that starts with a buy order
    followed by a sell order
    """

    use GenServer, restart: :transient
    alias Elementary.Channels.Channel
    alias Elementary.Traders.Instrumenter
    require Logger

    @client Elementary.Exchanges.Fake

    def start_link(spec, [q, p]) do
      GenServer.start_link(__MODULE__, [q, p, spec])
    end

    def init([q, p, %{"name" => name}]) do
      Channel.subscribe(name)
      {:ok, %{buy: nil, sell: nil, symbol: name}, {:continue, {:buy, q, p}}}
    end

    def handle_continue({:buy, q, p}, %{symbol: s} = state) do
      {:ok, order} = @client.buy(s, q, p)
      state = %{state | buy: order}
      Instrumenter.order_created(s, :buy)
      {:noreply, state}
    end

    def handle_info(
          %{"event" => "trade", "buyer_order_id" => order_id},
          %{buy: %{"order_id" => order_id, "status" => "FILLED"}} = state
        ) do
      {:noreply, state}
    end

    def handle_info(
          %{"event" => "trade", "buyer_order_id" => order_id},
          %{
            buy: %{
              "symbol" => symbol,
              "time" => timestamp,
              "order_id" => order_id,
              "status" => "NEW"
            }
          } = state
        ) do
      state =
        case @client.find_order(symbol, timestamp, order_id) do
          {:ok,
           %{"status" => "FILLED", "symbol" => s, "orig_qty" => q, "price" => buy_price} = buy} ->
            sell_price = buy_price * 1.1
            {:ok, sell} = @client.sell(s, q, sell_price)
            Instrumenter.order_filled(s, :buy)
            Instrumenter.order_created(s, :sell)
            %{state | buy: buy, sell: sell}

          {:ok, order} ->
            Logger.warn(
              "our buy order was published but it does not seem to be filled: #{inspect(order)}"
            )

            %{state | buy: order}
        end

      {:noreply, state}
    end

    def handle_info(_, state), do: {:noreply, state}
  end

  defmodule Instrumenter do
    @moduledoc """
    A symbol instrumenter based on Prometheus

    Defines all the metrics that we expose in relation
    to trade orders
    """

    use Prometheus.Metric

    def setup do
      Counter.declare(
        name: :orders_created,
        help: "Number of orders created",
        labels: [:symbol, :side]
      )

      Counter.declare(
        name: :orders_filled,
        help: "Number of orders filled",
        labels: [:symbol, :side]
      )
    end

    def order_created(symbol, side) do
      Counter.inc(name: :orders_created, labels: [symbol, side])
    end

    def order_filled(symbol, side) do
      Counter.inc(name: :orders_filled, labels: [symbol, side])
    end
  end
end
