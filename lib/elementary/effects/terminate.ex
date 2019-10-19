defmodule Elementary.Effects.Terminate do
  @moduledoc false

  use Elementary.Effect, :terminate

  def effect(owner, _) do
    terminate(owner)
  end
end
