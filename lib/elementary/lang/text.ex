defmodule Elementary.Lang.Text do
  @moduledoc false

  use Elementary.Provider,
    kind: "text",
    module: __MODULE__

  alias Elementary.Kit

  defstruct [
    spec: %{}
  ]

  def parse(%{ "text" => spec}, _providers) when is_binary(spec) or is_number(spec) or is_atom(spec) do
    {:ok, %__MODULE__{spec: "#{spec}"}}
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def compile(text, _), do: "\"#{text.spec}\""



  def ast(text, _) do
    {:text, text.spec}
  end
end
