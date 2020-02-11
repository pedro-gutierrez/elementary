defmodule Elementary.Test do
  @moduledoc false

  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def run(test, settings \\ "local", tag \\ nil) do
    with {:ok, mod} <- Elementary.Index.get("test", test),
         {:ok, settings} <- Elementary.Index.get("settings", settings) do
      DynamicSupervisor.start_child(__MODULE__, {mod, settings: settings, tag: tag})
    end
  end
end
