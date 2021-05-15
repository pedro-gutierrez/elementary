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

    def start_link(%{name: name} = spec) do
      Supervisor.start_link(__MODULE__, spec, name: name)
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

    def child_spec(%{"name" => name} = spec) do
      name = String.to_atom(name)

      inner_spec = %{name: name}

      inner_spec =
        case spec["spec"] do
          %{"events" => events} ->
            Map.put(inner_spec, :events, events)

          _ ->
            inner_spec
        end

      %{
        id: name,
        start:
          {__MODULE__, :start_link,
           [
             inner_spec
           ]}
      }
    end

    def init(%{name: name} = spec) do
      :ok = :pg2.create(name)

      Supervisor.init(
        [
          {Writer, spec}
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

    @default_size 25 * 1024 * 1000

    alias Elementary.Stores.Store
    alias Elementary.Kit
    alias Elementary.Channels.Instrumenter
    require Logger

    def start_link(spec) do
      GenServer.start_link(__MODULE__, spec)
    end

    def init(%{name: name} = spec) do
      :pg2.join(name, self())

      case spec[:events] do
        nil ->
          :ok

        events ->
          Enum.each(events, fn event ->
            col = "#{name}-#{event}"
            :ok = Store.ensure_collection(:default, col, %{"size" => @default_size})
          end)
      end

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
