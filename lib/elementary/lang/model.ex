defmodule Elementary.Lang.Model do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit
  alias Elementary.Lang.Dict

  defstruct spec: %Dict{}

  def default() do
    %{}
  end

  def parse(spec, providers) do
    case Kit.parse_spec(spec, providers) do
      {:ok, parsed} ->
        {:ok, %__MODULE__{spec: parsed}}

      {:error, e} ->
        Kit.error(:parse_error, %{
          spec: spec,
          reason: e
        })
    end
  end

  def ast(model, index) do
    model.spec
    |> model.spec.__struct__.ast(index)
  end
end
