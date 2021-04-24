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

    @client Elementary.Exchanges.Fake

    use GenServer
    alias Elementary.Channels.Channel
    require Logger

    def start_link(%{"name" => name} = spec) do
      name = String.to_atom("#{name}_trader")
      GenServer.start_link(__MODULE__, spec, name: name)
    end

    def child_spec(%{"name" => name} = spec) do
      %{
        id: name,
        start: {__MODULE__, :start_link, [spec]}
      }
    end

    def init(%{"name" => name}) do
      Channel.subscribe(name)
      {:ok, %{buy: nil, sell: nil, symbol: name}}
    end

    def handle_info(%{"event" => "trade", "s" => s, "p" => p}, %{buy: nil} = state) do
      {:ok, p} = Decimal.cast(p)
      p = Decimal.to_float(p)
      {:ok, q} = Decimal.cast(10)
      q = Decimal.to_float(q)

      {:ok, order} = @client.buy(%{symbol: s, q: q, p: p})
      state = %{state | buy: order}
      # Logger.info("trader has buy order #{inspect(state)}")
      {:noreply, state}
    end

    def handle_info(
          %{"event" => "trade", "buyer_order_id" => order_id},
          %{buy: %{order_id: order_id, status: "FILLED"}} = state
        ) do
      {:noreply, state}
    end

    def handle_info(
          %{"event" => "trade", "buyer_order_id" => order_id},
          %{buy: %{symbol: symbol, time: timestamp, order_id: order_id}} = state
        ) do
      {:ok, _order} = @client.order(symbol, timestamp, order_id)

      # Logger.info("found buy order #{inspect(order)}")
      {:noreply, state}
    end

    def handle_info(_, state), do: {:noreply, state}
  end
end
