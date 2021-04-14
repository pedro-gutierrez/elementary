defmodule Elementary.Subscriptions do
  @moduledoc false

  use Supervisor
  alias Elementary.Index
  alias Elementary.Subscriptions.Subscription
  alias Elementary.Topics

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    Index.specs("subscription")
    |> Enum.map(&subscription_spec(&1))
    |> Supervisor.init(strategy: :one_for_one)
  end

  defp subscription_spec(spec) do
    {Subscription, spec}
  end

  defmodule Subscription do
    use GenServer
    @moduledoc false

    def start_link(spec) do
      GenServer.start_link(__MODULE__, spec)
    end

    def init(%{"name" => name, "spec" => %{"topic" => topic}} = spec) do
      IO.inspect(subscription: name, topic: topic)
      :ok = Topics.subscribe(topic)
      {:ok, spec}
    end

    def handle_info(data, %{"name" => name, "spec" => %{"topic" => topic}} = spec) do
      IO.inspect(subscription: name, topic: topic, data: data)
      {:noreply, spec}
    end
  end
end
