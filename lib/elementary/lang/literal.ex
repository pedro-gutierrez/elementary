defmodule Elementary.Lang.Literal do
  @moduledoc false

  use Elementary.Provider,
    kind: "literal",
    module: __MODULE__

  alias Elementary.Kit

  defstruct spec: %{}

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def ast(literal, index) do
    literal.spec.__struct__.ast(literal.spec, index)
  end

  def decoder_ast(inner, lv) do
    inner.spec.__struct__.decoder_ast(inner.spec, lv)
  end
end
