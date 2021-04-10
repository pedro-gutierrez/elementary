defmodule Elementary.Topics do
  @moduledoc false

  use Supervisor
  alias Elementary.Index

  def subscribe(topic) do
    topic
    |> String.to_existing_atom()
    |> Phoenix.PubSub.subscribe("data")
  end

  def publish(topic, data) do
    topic
    |> String.to_existing_atom()
    |> Phoenix.PubSub.broadcast("data", data)
  end

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    names = topic_names()

    res =
      names
      |> Enum.map(fn name ->
        {Phoenix.PubSub, name: name}
      end)
      |> Supervisor.init(strategy: :one_for_one)

    names
    |> Enum.each(fn name ->
      IO.inspect(topic: name)
    end)

    res
  end

  defp topic_names do
    Index.specs("topic")
    |> Enum.map(fn %{"name" => name} ->
      String.to_atom(name)
    end)
  end
end
