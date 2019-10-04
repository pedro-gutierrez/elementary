defmodule Elementary.Lang.Init do
  @moduledoc false

  use Elementary.Provider
  alias Elementary.Kit

  alias Elementary.Lang.{Clause}

  defstruct spec: %{}

  def default() do
    %__MODULE__{spec: Clause.default()}
  end

  def parse(%{"init" => init}, providers) do
    parse_init(init, providers)
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def parse_init(raw, providers) do
    case Clause.parse(raw, providers) do
      {:ok, clause} ->
        {:ok, %__MODULE__{spec: clause}}

      {:error, _} = e ->
        e
    end
  end

  def ast(parsed, index) do
    {:clause, _, expr_ast} = parsed.spec.__struct__.ast(parsed.spec, index)
    expr_ast
  end
end
