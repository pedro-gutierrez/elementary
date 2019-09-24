defmodule Elementary.Lang.Init do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Lang.{Clause}

  @default %{"model" => %{}, "cmds" => []}

  defstruct spec: %{}

  def parse(%{"init" => init}, providers) do
    parse_init(init, providers)
  end

  def parse(%{}, providers) do
    parse(%{"init" => @default}, providers)
  end

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
    IO.inspect(init: expr_ast)
    expr_ast
  end
end
