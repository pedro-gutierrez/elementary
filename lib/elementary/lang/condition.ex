defmodule Elementary.Lang.Condition do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit

  defstruct spec: %{}

  def default() do
    true
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

  def compile(%{spec: true}, _) do
    ["true"]
  end
end
