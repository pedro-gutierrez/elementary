defmodule Elementary.Ast do
  @moduledoc false

  @line [line: 1]

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
       {quoted(k), quoted(v)}
     end)}
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
         do: clauses |> Enum.map(&quoted(&1))
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
    quoted(
      {:with,
       Enum.map(vars, fn {v, vexpr} ->
         {:generator, {:ok, {:var, v}}, vexpr}
       end), {:ok, expr}, :error_clause}
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
    # IO.inspect(mod: mod, code: code)
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

  defp aggregated({:map, m0}, {:map, m1}) do
    {:map, m0 ++ m1}
  end

  defp aggregated({:ok, v0}, {:ok, v1}) do
    {:ok, aggregated(v0, v1)}
  end

  defp aggregated(l1, l2) when is_list(l1) and is_list(l2) do
    l1 ++ l2
  end
end
