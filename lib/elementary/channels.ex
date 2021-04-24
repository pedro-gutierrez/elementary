defmodule Elementary.Channels do
  @moduledoc """
  A supervisor for all configured channels
  """

  use Supervisor

  alias Elementary.Index
  alias Elementary.Channels.Channel

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    Index.specs("channel")
    |> Enum.map(&Channel.child_spec(&1))
    |> Supervisor.init(strategy: :one_for_one)
  end

  defmodule Channel do
    @moduledoc """
    A channel takes data, maybe persists it, then
    broadcasts it over a pub/sub topic.
    """

    use Supervisor

    require Logger
    alias Elementary.Channels.Instrumenter
    alias Elementary.Channels.Writer

    def name(name) when is_atom(name), do: name
    def name(name), do: String.to_atom(name)

    def start_link(name) do
      Supervisor.start_link(__MODULE__, name, name: name)
    end

    def publish(channel, %{"event" => event} = data) do
      channel = name(channel)
      Instrumenter.event_in(channel, event, "total")
      for pid <- :pg2.get_members(channel), do: send(pid, data)
      :ok
    end

    def subscribe(channel) do
      :ok =
        channel
        |> name()
        |> :pg2.join(self())
    end

    def child_spec(%{"name" => name}) do
      name = String.to_atom(name)

      %{
        id: name,
        start: {__MODULE__, :start_link, [name]}
      }
    end

    def init(name) do
      :ok = :pg2.create(name)

      IO.inspect(channel: name)

      Supervisor.init(
        [
          {Writer, name}
        ],
        strategy: :one_for_one
      )
    end
  end

  defmodule Writer do
    @moduledoc """
    A module that subscribes to the topic for the channel,
    and persists every message received
    """
    use GenServer

    alias Elementary.Stores.Store
    alias Elementary.Kit
    alias Elementary.Channels.Instrumenter
    require Logger

    def start_link(name) do
      GenServer.start_link(__MODULE__, name)
    end

    def init(name) do
      :pg2.join(name, self())
      {:ok, name}
    end

    def handle_info(%{"event" => event} = data, channel) do
      start = Kit.millis()

      case Store.insert(:default, "#{channel}-#{event}", data) do
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
