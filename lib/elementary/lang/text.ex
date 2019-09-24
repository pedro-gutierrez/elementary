defmodule Elementary.Lang.Text do
  @moduledoc false

  use Elementary.Provider,
    kind: "text",
    module: __MODULE__

  alias Elementary.Kit
  alias Elementary.Lang.Literal

  defstruct spec: %{}

  def parse(%{"text" => spec}, _providers)
      when is_binary(spec) or is_number(spec) or is_atom(spec) do
    {:ok, %Literal{spec: %__MODULE__{spec: "#{spec}"}}}
  end

  def parse(spec, providers) when is_binary(spec) do
    parse(%{"text" => spec}, providers)
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def ast(text, _) do
    {:ok, {:text, text.spec}}
  end

  def decoder_ast(%{spec: literal}, lv) when is_binary(literal) do
    {{:text, literal}, [], {:text, literal}, lv}
  end
end
