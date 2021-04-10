defmodule Elementary.Channel do
  @moduledoc """
  A channel takes data, maybe persists it, then
  broadcasts it over a pub/sub topic.
  """

  use Supervisor

  require Logger
  alias Elementary.Stores.Store
  alias Elementary.Channel.Instrumenter

  def start_link(name) do
    Supervisor.start_link(__MODULE__, name)
  end

  def send(channel, event, data) do
    case Store.insert("symbols", "#{channel}-#{event}", data) do
      :ok ->
        Instrumenter.event_in(channel, event, "success")
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
    end

    def event_in(channel, event, status) do
      Counter.inc(name: :events_in_total, labels: [channel, event, status])
    end
  end
end
