defmodule Elementary.Init do
  @moduledoc false

  use Elementary.Provider
  alias Elementary.Kit

  alias Elementary.Clause

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
    {:clause, _, ast} = parsed.spec.__struct__.ast(parsed.spec, index)
    data_var = Elementary.Ast.fn_clause_var_name(ast, :data)
    [{:fun, :init, [data_var], ast}]
  end
end
