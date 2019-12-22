defmodule Elementary.Uuid do
  @moduledoc false

  use Elementary.Effect, name: :uuid

  def handle_call(_) do
    {:ok, %{"uuid" => UUID.uuid4()}}
  end
end
