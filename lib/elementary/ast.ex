defmodule Elementary.Ast do
  @moduledoc false

  @line [line: 1]

  @type ast() :: tuple()

  defp symbol(name) when is_binary(name) do
    name |> String.to_atom()
  end

  defp symbol(name) when is_atom(name) do
    name
  end

  def filter({:module, _, body}, {:fun, name}) do
    body
    |> Enum.filter(fn
      {:fun, ^name, _, _, _} -> true
      {:fun, ^name, _, _} -> true
      {:fun, ^name, _} -> true
      _ -> false
    end)
  end

  def filter(asts, {:module, names}) when is_list(asts) and is_list(names) do
    asts
    |> Enum.filter(fn
      {:module, name, _} ->
        Enum.member?(names, name)

      _ ->
        false
    end)
  end

  def quoted(:empty_map) do
    {:map, []}
  end

  def quoted({:module, name, body}) do
    {:defmodule, @line,
     [
       {:__aliases__, @line, [name |> symbol()]},
       [do: {:__block__, [], quoted(body)}]
     ]}
  end

  def quoted({:usage, name, params}) do
    {:use, @line,
     [
       {:__aliases__, @line, name |> symbol()},
       params
     ]}
  end

  def quoted({:usage, name}) do
    quoted({:usage, name, []})
  end

  def quoted({:fun, name, params, body}) do
    quoted({:fun, name, params, [], body})
  end

  def quoted({:fun, name, params, [], body}) do
    {:def, @line,
     [
       {name |> symbol(), @line,
        params
        |> Enum.map(&quoted_param(&1))},
       [do: quoted(body)]
     ]}
  end

  def quoted({:fun, name, params, guards, body}) do
    {:def, @line,
     [
       {:when, @line,
        [
          {name |> symbol(), @line,
           params
           |> Enum.map(&quoted_param(&1))},
          quoted_guards(guards)
        ]},
       [do: quoted(body)]
     ]}
  end

  def quoted(model: model, cmds: cmds) do
    case {literal?(model), literal?(cmds)} do
      {true, true} ->
        quoted({:ok, extract_literal(model), extract_literal(cmds)})

      {_, _} ->
        quoted({:let, [model: model, cmds: cmds], {:ok, {:var, :model}, {:var, :cmds}}})
    end
  end

  def quoted({:call, name, params}) do
    {name, @line, quoted(params)}
  end

  def quoted({:call, mod, fun, params}) do
    {{:., @line, [{:__aliases__, @line, [mod]}, fun]}, @line, quoted(params)}
  end

  def quoted({:and, items}) do
    {:and, @line, items |> quoted()}
  end

  def quoted({:fun, name, body}) do
    quoted({:fun, name, [], body})
  end

  def quoted(list) when is_list(list) do
    list |> Enum.map(&quoted(&1))
  end

  def quoted({:var, name}) when is_atom(name) do
    {name, @line, nil}
  end

  def quoted({:var, name}) when is_binary(name) do
    {name |> String.to_atom(), @line, nil}
  end

  def quoted({:symbol, str}) when is_binary(str) do
    str |> String.to_atom()
  end

  def quoted({:symbol, atom}) when is_atom(atom) do
    atom
  end

  def quoted({:props, props}) do
    props
    |> Enum.map(fn {k, v} ->
      {k, quoted(v)}
    end)
  end

  def quoted({:map, map}) do
    {:%{}, [],
     Enum.map(map, fn {k, v} ->
       {quoted(k), extract_literal(quoted(v))}
     end)}
  end

  def quoted({:dict, entries}) do
    case split_dict(entries) do
      {literals, []} ->
        quoted(
          {:ok,
           {:map,
            Enum.map(literals, fn {_, k, v} ->
              {k, v}
            end)}}
        )

      {literals, exprs} ->
        {_, generators} =
          Enum.reduce(exprs, {0, []}, fn {_, _, e}, {i, gens} ->
            {i + 1, [{var(i), e} | gens]}
          end)

        {_, values} =
          Enum.reduce(exprs, {0, []}, fn {_, k, _}, {i, values} ->
            {i + 1, [{k, {:var, var(i)}} | values]}
          end)

        ast =
          quoted(
            {:let, generators,
             {:ok,
              {:map,
               values ++
                 Enum.map(literals, fn {_, k, v} ->
                   {k, v}
                 end)}}}
          )

        ast
    end
  end

  def quoted({:list, items}) when is_list(items) do
    quoted(items)
  end

  def quoted({:tuple, items}) when is_list(items) do
    {:{}, @line, quoted(items)}
  end

  def quoted({:text, text}) do
    "#{text}"
  end

  def quoted({:number, num}) do
    num
  end

  def quoted({:boolean, v}) do
    v
  end

  def quoted({:ok, value}) do
    {:ok, quoted(value)}
  end

  def quoted({:ok, value1, value2}) do
    quoted({:tuple, [:ok, value1, value2]})
  end

  def quoted({:error, reason}) do
    {:error, quoted(reason)}
  end

  def quoted({:error, reason, data}) do
    quoted({:error, {:map, [reason: reason, data: data]}})
  end

  def quoted({:error, reason, data, context}) do
    quoted({:error, {:map, [reason: reason, data: data, context: context]}})
  end

  def quoted({:condition, clauses}) do
    {:cond, @line,
     [
       [
         do: clauses |> Enum.map(&quoted(&1))
       ]
     ]}
  end

  def quoted({:clause, guard, expression}) do
    {:->, @line,
     [
       [guard |> quoted()],
       expression |> quoted()
     ]}
  end

  def quoted({:case, expr, clauses}) do
    {:case, @line,
     [
       quoted(expr),
       [
         do:
           Enum.map(clauses, fn {condition, expr} ->
             quoted({:clause, condition, expr})
           end)
       ]
     ]}
  end

  def quoted(:error_clause) do
    [
      {:->, @line,
       [
         [
           {:=, @line,
            [
              {:error, {:_, @line, nil}},
              {:e, @line, nil}
            ]}
         ],
         {:e, @line, nil}
       ]},
      {:->, @line, [[{:other, @line, nil}], {:error, {:other, @line, nil}}]}
    ]
  end

  def quoted({:let, vars}) do
    quoted(
      {:with,
       Enum.map(vars, fn {v, expr} ->
         {:generator, {:ok, {:var, v}}, expr}
       end),
       {:tuple,
        [:ok] ++
          Enum.map(vars, fn {v, _} ->
            {:var, v}
          end)}, :error_clause}
    )
  end

  def quoted({:let, vars, expr}) do
    quoted({:let, vars, expr, :error_clause})
  end

  def quoted({:let, vars, expr, error}) do
    quoted(
      {:with,
       Enum.map(vars, fn {v, vexpr} ->
         {:generator, {:ok, {:var, v}}, vexpr}
       end), expr, error}
    )
  end

  def quoted({:with, generators, success}) do
    quoted({:with, generators, success, :error_clause})
  end

  def quoted({:with, generators, success, errors}) do
    {:with, @line,
     (generators
      |> Enum.map(&quoted(&1))) ++
       [
         [
           do: quoted(success),
           else: quoted(errors)
         ]
       ]}
  end

  def quoted({:generator, left, right}) do
    {:<-, @line,
     [
       quoted(left),
       quoted(right)
     ]}
  end

  def quoted(other)
      when is_atom(other) or is_binary(other) or is_number(other) or is_boolean(other) do
    other
  end

  def quoted_param(var) when is_atom(var) do
    {var, @line, nil}
  end

  def quoted_param(other) do
    quoted(other)
  end

  def quoted_guards([single]) do
    single |> quoted()
  end

  def quoted_guards(guards) do
    {:and, @line, guards |> Enum.map(&quoted(&1))}
  end

  def compiled(asts) when is_list(asts) do
    Code.compiler_options(ignore_module_conflict: true)

    Enum.reduce_while(asts, [], fn ast, acc ->
      case compiled(ast) do
        {:ok, mod} ->
          {:cont, [mod | acc]}

        {:error, _} = e ->
          {:halt, e}
      end
    end)
    |> case do
      {:error, _} = e ->
        e

      mods ->
        {:ok, Enum.reverse(mods)}
    end
  end

  def compiled({:module, mod, _} = ast) do
    ast
    |> quoted()
    |> compiled(mod)
  end

  def compiled(code, _mod) do
    [{mod, _}] = Code.compile_quoted(code)
    {:ok, mod}
  end

  def aggregated(asts) do
    asts
    |> Enum.reduce(nil, fn expr, combined ->
      aggregated(combined, expr)
    end)
  end

  defp aggregated(nil, other) do
    other
  end

  defp aggregated([model: m0, cmds: c0], model: m1, cmds: c1) do
    [model: aggregated(m0, m1), cmds: aggregated(c0, c1)]
  end

  defp aggregated({:dict, entries1}, {:dict, entries2}) do
    {:dict, entries1 ++ entries2}
  end

  defp aggregated({:let, [model: m0, cmds: cmds0]}, {:let, [model: m1, cmds: cmds1]}) do
    {:let, [model: aggregated(m0, m1), cmds: aggregated(cmds0, cmds1)]}
  end

  defp aggregated({:let, vars0, {:map, keys0}}, {:let, vars1, {:map, keys1}}) do
    with {_, vars} <-
           (vars0 ++ vars1)
           |> Enum.reduce({0, []}, fn {_, expr}, {i, vars} ->
             {i + 1, [{"v#{i}", expr} | vars]}
           end),
         {_, keys} <-
           (keys0 ++ keys1)
           |> Enum.reduce({0, []}, fn {k, _}, {i, keys} ->
             {i + 1, [{k, {:var, "v#{i}"}} | keys]}
           end) do
      {:let, Enum.reverse(vars), {:map, Enum.reverse(keys)}}
    end
  end

  defp aggregated({:ok, {:map, _} = map1, cmds1}, {:ok, {:map, _} = map2, cmds2}) do
    {:ok, aggregated(map1, map2), aggregated(cmds1, cmds2)}
  end

  defp aggregated({:map, m0}, {:map, m1}) do
    {:map, m0 ++ m1}
  end

  defp aggregated({:ok, v0}, {:ok, v1}) do
    {:ok, aggregated(v0, v1)}
  end

  defp aggregated(l1, l2) when is_list(l1) and is_list(l2) do
    l1 ++ l2
  end

  defp split_dict(entries) do
    Enum.reduce(entries, {[], []}, fn
      {:literal, _, _} = l, {literals, exprs} ->
        {[l | literals], exprs}

      {:expression, _, _} = e, {literals, exprs} ->
        {literals, [e | exprs]}
    end)
  end

  @doc """
  Analyzes the given ast, and determines whether or not
  the given variable is being used. This is to eliminate compiler
  warnings on unused variables
  """
  @spec uses_var?(ast :: ast(), var :: atom()) :: boolean()
  def uses_var?(ast, var) do
    ast |> inspect() |> String.contains?(":#{var}")
  end

  @doc """
  Helper function that returns a proper function clause variable
  name, depending on whether or not, the variable is actually
  being used in the given ast.
  """
  @spec fn_clause_var_name(ast :: ast(), var :: atom()) :: atom()
  def fn_clause_var_name(ast, var) do
    case uses_var?(ast, var) do
      true ->
        var

      false ->
        String.to_atom("_#{var}")
    end
  end

  defp literal?({:dict, dict}) do
    case split_dict(dict) do
      {_, []} -> true
      _ -> false
    end
  end

  defp literal?({:ok, ast}) do
    literal?(ast)
  end

  defp literal?(items) when is_list(items) do
    Enum.all?(items, &literal?(&1))
  end

  defp literal?(other)
       when is_number(other) or is_binary(other) or is_atom(other) or is_boolean(other),
       do: true

  defp literal?(_), do: false

  defp extract_literal({:ok, ast}), do: ast
  defp extract_literal(ast), do: ast

  defp var(i), do: String.to_atom("v#{i}")
end
