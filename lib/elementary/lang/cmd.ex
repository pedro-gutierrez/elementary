defmodule Elementary.Lang.Cmd do
  @moduledoc false

  use Elementary.Provider

  alias Elementary.Kit

  defstruct encoder: "",
            effect: ""

  def parse(%{"encoder" => enc, "effect" => effect}, _) do
    {:ok, %__MODULE__{encoder: enc, effect: effect}}
  end

  def parse(spec, _) do
    Kit.error(:not_supported, spec)
  end

  def ast(%{effect: effect, encoder: encoder}, _) when is_binary(effect) and is_binary(encoder) do
    {:tuple, [{:symbol, effect}, {:symbol, encoder}]}
  end

  def ast(%{effect: effect}, _) when is_binary(effect) do
    {:symbol, effect}
  end
end
