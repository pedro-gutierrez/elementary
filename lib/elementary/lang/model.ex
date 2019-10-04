defmodule Elementary.Lang.Model do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit
  alias Elementary.Lang.Dict

  defstruct spec: %Dict{}

  def default() do
    %__MODULE__{spec: Dict.default()}
  end

  def parse(%{"model" => spec}, providers) do
    case Dict.parse(spec, providers) do
      {:ok, parsed} ->
        {:ok, %__MODULE__{spec: parsed}}

      {:error, e} ->
        Kit.error(:parse_error, %{
          spec: spec,
          reason: e
        })
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def ast(model, index) do
    model.spec
    |> model.spec.__struct__.ast(index)
  end

  def literal?(model) do
    model.spec.__struct__.literal?(model.spec)
  end
end
