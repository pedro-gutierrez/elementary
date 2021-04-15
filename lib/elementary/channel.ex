defmodule Elementary.Channel do
  @moduledoc """
  A channel takes data, maybe persists it, then
  broadcasts it over a pub/sub topic.
  """

  use Supervisor

  require Logger
  alias Elementary.Stores.Store
  alias Elementary.Channel.Instrumenter
  alias Elementary.Kit

  def start_link(name) do
    Supervisor.start_link(__MODULE__, name)
  end

  def send(channel, %{"event" => event} = data) do
    channel = String.to_existing_atom(channel)
    Instrumenter.event_in(channel, event, "total")
    Phoenix.PubSub.broadcast(channel, "data", data)
    :ok
  end

  def subscribe(channel) do
    IO.inspect(subscribe: channel)
  end

  def child_spec(name) do
    %{
      id: name,
      start: {__MODULE__, :start_link, [name]}
    }
  end

  def init(name) do
    IO.inspect(channel: name)

    Supervisor.init(
      [
        {Phoenix.PubSub, name: name},
        {Elementary.Channel.Writer, name}
      ],
      strategy: :one_for_one
    )
  end

  defmodule Writer do
    @moduledoc """
    A module that subscribes to the topic for the channel,
    and persists every message received
    """

    use GenServer

    def start_link(name) do
      GenServer.start_link(__MODULE__, name)
    end

    def init(name) do
      Phoenix.PubSub.subscribe(name, "data")
      {:ok, name}
    end

    def handle_info(%{"event" => event} = data, channel) do
      start = Kit.millis()

      case Store.insert("symbols", "#{channel}-#{event}", data) do
        :ok ->
          millis = Kit.millis_since(start)
          Instrumenter.event_in(channel, event, "success", millis)
          :ok

        {:error, e} ->
          Instrumenter.event_in(channel, event, "error")
          Logger.warn("Error writing to #{channel}-#{event}: #{inspect(e)}")
      end

      {:noreply, channel}
    end
  end

  defmodule Instrumenter do
    @moduledoc """
    A channel instrumenter based on 
    Prometheus
    """

    use Prometheus.Metric

    def setup do
      Counter.declare(
        name: :events_in_total,
        help: "Events in total",
        labels: [:channel, :event, :status]
      )

      Histogram.new(
        name: :event_storage_overhead,
        buckets: [10, 50, 100, 300, 500, 750, 1000],
        help: "Event storage overhead"
      )
    end

    def event_in(channel, event, status) do
      Counter.inc(name: :events_in_total, labels: [channel, event, status])
    end

    def event_in(channel, event, status, time) do
      event_in(channel, event, status)

      Histogram.observe([name: :event_storage_overhead], time)
    end
  end
end
