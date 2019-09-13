defmodule Elementary.Lang.Cmd do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit

  defstruct [
    encoder: "",
    effect: ""
  ]

  def parse(%{ "encoder" => enc, "effect" => effect}, _) do
    {:ok, %__MODULE__{encoder: enc, effect: effect}}
  end

  def parse(spec, _) do
    Kit.error(:not_supported, spec)
  end

  def compile(_cmds, _providers) do
    [":ok"]
  end

end
