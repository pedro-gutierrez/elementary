defmodule Elementary.Lang.Model do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit
  alias Elementary.Lang.Dict

  defstruct spec: %Dict{}

  def parse(%{"model" => spec} = init, providers) do
    case Kit.parse_spec(spec, providers) do
      {:ok, parsed} ->
        {:ok, %__MODULE__{spec: parsed}}

      {:error, e} ->
        Kit.error(:parse_error, %{
          spec: init,
          reason: e
        })
    end
  end

  def parse(_, _) do
    {:ok, %__MODULE__{}}
  end

  def ast(model, index) do
    model.spec
    |> model.spec.__struct__.ast(index)
  end
end
