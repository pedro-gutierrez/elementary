defmodule Elementary.Update do
  @moduledoc false

  use Elementary.Provider

  alias Elementary.Kit
  alias Elementary.Clause

  defstruct spec: %{}

  def parse(%{"update" => spec} = update, providers) when is_map(spec) do
    case parse_updates(spec, providers) do
      {:error, e} ->
        Kit.error(:parse_error, %{
          spec: update,
          reason: e
        })

      updates ->
        {:ok, %__MODULE__{spec: updates}}
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  defp parse_updates(updates, providers) do
    updates
    |> Enum.reduce_while(%{}, fn {event, clauses}, acc ->
      case clauses |> parse_clauses(providers) do
        {:error, e} ->
          {:halt, Kit.error(:parse_error, %{reason: e})}

        parsed ->
          {:cont, Map.put(acc, event, Enum.reverse(parsed))}
      end
    end)
  end

  defp parse_clauses(many, providers) when is_list(many) do
    many
    |> Enum.reduce_while([], fn clause, acc ->
      case clause |> Clause.parse(providers) do
        {:error, e} ->
          {:halt, Kit.error(:parse_error, %{reason: e})}

        {:ok, parsed} ->
          {:cont, [parsed | acc]}
      end
    end)
  end

  defp parse_clauses(single, providers) when is_map(single) do
    parse_clauses([single], providers)
  end

  def ast(update, index) do
    (update.spec
     |> Enum.map(fn {event, clauses} ->
       ast = maybe_optimized(clauses, index)

       data_var = Elementary.Ast.fn_clause_var_name(ast, :data)

       {:fun, :update, [{:text, event}, data_var, :_context], ast}
     end)) ++
      [
        not_implemented_ast()
      ]
  end

  defp maybe_optimized(clauses, index) do
    clauses =
      clauses
      |> Enum.map(fn c ->
        Clause.ast(c, index)
      end)
      |> Enum.reduce_while([], fn
        {:clause, {:boolean, true}, _} = c, acc ->
          {:halt, [c | acc]}

        c, acc ->
          {:cont, [c | acc]}
      end)

    case clauses do
      [{:clause, _, body}] ->
        body

      _ ->
        {:conditon, clauses |> Enum.reverse()}
    end
  end

  def not_implemented_ast() do
    {:fun, :update, [:_, :_, :_], {:error, :no_update}}
  end
end
