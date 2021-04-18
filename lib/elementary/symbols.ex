defmodule Elementary.Symbols do
  @moduledoc false

  use Supervisor
  alias Elementary.Index
  alias Elementary.Symbols.{ChannelsSup, TradesSup, Trades, ExchangeInfo}
  alias Elementary.Channels.Channel

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def resume_trades() do
    Elementary.Symbols.TradesSup
    |> Process.whereis()
    |> Process.exit(:kill)
  end

  def init(_) do
    [
      ChannelsSup,
      TradesSup,
      ExchangeInfo
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end

  defmodule ChannelsSup do
    @moduledoc """
    A supervisor for all channels associated 
    to symbols. 
    """
    use Supervisor

    def start_link(opts) do
      Supervisor.start_link(__MODULE__, opts)
    end

    def init(_) do
      Index.specs("symbol")
      |> Enum.map(&Channel.child_spec(&1))
      |> Supervisor.init(strategy: :one_for_one)
    end
  end

  defmodule TradesSup do
    @moduledoc """
    A supervisor for all symbol trades worker
    """
    use Supervisor

    def start_link(opts) do
      Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    end

    def init(_) do
      Index.specs("symbol")
      |> Enum.map(fn spec ->
        {Trades, spec}
      end)
      |> Supervisor.init(strategy: :one_for_one)
    end
  end

  defmodule Trades do
    @moduledoc """
    A worker that subscribes to symbol trades
    and emits them to the rest of the application
    """
    use WebSockex

    alias Elementary.Symbols.Instrumenter

    require Logger

    def start_link(%{"name" => name, "spec" => inner} = spec) do
      inner = Map.put(inner, "symbol", String.upcase(name))

      spec = Map.put(spec, "spec", inner)

      {:ok, pid} =
        WebSockex.start_link("wss://stream.binance.com:9443/ws/#{name}@trade", __MODULE__, spec)

      IO.inspect(symbol: String.to_atom(name))
      {:ok, pid}
    end

    def child_spec(%{"name" => name} = spec) do
      %{
        id: name,
        start: {__MODULE__, :start_link, [spec]}
      }
    end

    def handle_frame(
          {:text, msg},
          %{
            "name" => name,
            "spec" => %{"symbol" => symbol}
          } = spec
        ) do
      with {:ok, %{"e" => "trade", "s" => ^symbol} = trade} <- Jason.decode(msg) do
        trade =
          Map.merge(trade, %{
            "s" => name,
            "event" => "trade"
          })

        Channel.send(name, trade)
      else
        other ->
          Logger.warn("Unexpected frame from #{symbol}: #{inspect(other)}")
      end

      {:ok, spec}
    end

    def handle_connect(_conn, %{"name" => name} = state) do
      Instrumenter.connected(name)
      Logger.info("Websocket #{name} connected")
      {:ok, state}
    end

    def handle_disconnect(_conn, %{"name" => name} = state) do
      Instrumenter.disconnected(name)
      Logger.info("Websocket #{name} disconnected")
      {:reconnect, state}
    end

    def terminate(reason, %{"name" => name}) do
      Instrumenter.disconnected(name)
      Logger.warn("Websocket #{name} terminated: #{inspect(reason)}")
      exit(:normal)
    end
  end

  defmodule ExchangeInfo do
    @moduledoc """
    A worker that fetches and emits the exchange information
    for those symbols that we are interested in
    """
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def init(_), do: {:ok, [], {:continue, :fetch}}

    def handle_continue(:fetch, state) do
      emit_exchange_info()
      {:noreply, state}
    end

    defp emit_exchange_info() do
      all_symbols =
        Index.specs("symbol")
        |> Enum.map(fn %{"name" => symbol} ->
          String.upcase(symbol)
        end)

      Binance.get_exchange_info()
      |> elem(1)
      |> Map.get(:symbols)
      |> Enum.filter(fn %{"symbol" => symbol} ->
        Enum.member?(all_symbols, symbol)
      end)
      |> Enum.map(fn %{"symbol" => symbol, "filters" => filters} = info ->
        filters =
          Enum.reduce(filters, %{}, fn %{"filterType" => type} = filter, acc ->
            type = String.downcase(type)
            filter = Map.drop(filter, ["filterType"])
            Map.put(acc, type, filter)
          end)

        info
        |> Map.put("symbol", String.downcase(symbol))
        |> Map.put("filters", filters)
      end)
      |> Enum.each(fn %{"symbol" => symbol} = info ->
        info = Map.put(info, "event", "info")
        Channel.send(symbol, info)
      end)
    end
  end

  defmodule Instrumenter do
    @moduledoc """
    A symbol instrumenter based on Prometheus

    Defines all the metrics that we expose in relation
    to symbol trade data consumption from Binance
    """

    use Prometheus.Metric

    def setup do
      Gauge.declare(
        name: :websocket_connection_status,
        help: "Websocket connection_status",
        labels: [:symbol]
      )
    end

    def disconnected(symbol) do
      Gauge.dec(name: :websocket_connection_status, labels: [symbol])
    end

    def connected(symbol) do
      Gauge.inc(name: :websocket_connection_status, labels: [symbol])
    end
  end
end
