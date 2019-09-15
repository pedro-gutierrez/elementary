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
    {name, @line, params |> Enum.map(&quoted_param(&1))}
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

  def quoted({:var, name}) do
    {name, @line, nil}
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
    items |> Enum.map(&quoted(&1))
  end

  def quoted({:tuple, items}) when is_list(items) do
    {:{}, @line, items |> Enum.map(&quoted(&1))}
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

  def quoted({:error, reason}) do
    {:error, quoted(reason)}
  end

  def quoted({:error, reason, data}) do
    quoted({:error, {:map, [reason: reason, data: data]}})
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

  def quoted(other) do
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

    asts
    |> Enum.map(fn ast ->
      [{mod, _}] = compiled(ast)
      mod
    end)
  end

  def compiled({:module, _, _} = ast) do
    code =
      ast
      |> quoted()

    IO.inspect(code)
    code |> Code.compile_quoted()
  end
end
