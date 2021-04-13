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

  def send(channel, event, data) do
    Instrumenter.event_in(channel, event, "total")

    case persist(channel, event, data) do
      {:ok, millis} ->
        Instrumenter.event_in(channel, event, "success", millis)
        :ok

      other ->
        Instrumenter.event_in(channel, event, "error")
        Logger.error("Error writing to #{channel}-#{event}: #{inspect(other)}")
    end
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
        {Phoenix.PubSub, name: name}
      ],
      strategy: :one_for_one
    )
  end

  defp persist(channel, event, data) do
    start = Kit.millis()
    res = Store.insert("symbols", "#{channel}-#{event}", data)
    {res, Kit.millis_since(start)}
  rescue
    e ->
      {:error, e}
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
