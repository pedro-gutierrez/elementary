defmodule Elementary.Lang.Condition do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit

  defstruct [
    spec: %{}
  ]

  def parse(%{ "when" => spec} = init, providers) do
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
    {:ok, %__MODULE__{spec: true}}
  end

  def compile(%{spec: true}, _) do
    ["true"]
  end

end
