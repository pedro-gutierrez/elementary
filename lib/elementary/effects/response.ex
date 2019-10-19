defmodule Elementary.Effects.Response do
  @moduledoc false

  use Elementary.Effect, :response

  def effect(owner, data) do
    data |> reply(owner)
  end
end
