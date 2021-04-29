defmodule Elementary.Metrics do
  @moduledoc """
  Everything about exporting Prometheus Metrics
  """

  use Supervisor

  @instruments [
    Elementary.Stores.Instrumenter,
    Elementary.Channels.Instrumenter,
    Elementary.Symbols.Instrumenter,
    Elementary.Traders.Instrumenter
  ]

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    @instruments
    |> Enum.each(fn mod -> mod.setup() end)

    Supervisor.init([], strategy: :one_for_one)
  end
end
