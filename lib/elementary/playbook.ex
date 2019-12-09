defmodule Elementary.Playbook do
  @moduledoc false

  use Elementary.Provider
  alias Elementary.Kit
  alias Elementary.Step

  defstruct rank: :high,
            name: nil,
            version: "1",
            playbooks: [],
            steps: []

  defmodule Step do
    defstruct title: nil, tags: [], spec: nil
  end

  def parse(
        %{
          "name" => name,
          "spec" => spec,
          "kind" => "playbook"
        },
        providers
      ) do
    with {:ok, playbooks} <- playbooks(spec, providers),
         {:ok, steps} <- steps(spec, providers) do
      {:ok,
       %__MODULE__{
         name: name,
         playbooks: playbooks,
         steps: steps
       }}
    else
      e ->
        e
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def ast(playbook, _) do
    IO.inspect(playbook: playbook)

    run_asts =
      (Enum.filter(playbook.steps, fn s ->
         true
         # s.spec.__struct__ == Elementary.Steps
       end)
       |> Enum.map(fn s ->
         {:fun, :run, [{:text, s.title}, :_context], {:tuple, [:ok, {:text, s.title}]}}
       end)) ++
        [{:fun, :run, [{:var, :_name}, :_context], {:tuple, [:error, :not_found]}}]

    index_by_tags =
      Enum.reduce(playbook.steps, %{}, fn s, tags ->
        Enum.reduce(s.tags, tags, fn t, tags ->
          values = Map.get(tags, t, [])
          Map.put(tags, t, [s.title | values])
        end)
      end)

    run_by_tag_asts =
      Enum.flat_map(index_by_tags, fn {t, steps} ->
        res = {:tuple, [:ok, {:list, Enum.reverse(steps)}]}
        [{:fun, :tagged, [{:symbol, t}], res}, {:fun, :tagged, [{:text, t}], res}]
      end) ++
        [{:fun, :tagged, [:_tag], {:tuple, [:error, :not_found]}}]

    [
      {:module, module_name(playbook),
       [
         {:fun, :kind, [], :playbook},
         {:fun, :name, [], {:symbol, playbook.name}}
       ] ++ run_asts ++ run_by_tag_asts}
    ]
  end

  def indexed(mods) do
    {:module, Elementary.Index.Playbook,
     (mods
      |> Enum.filter(fn m ->
        m.kind() == :playbook
      end)
      |> Enum.flat_map(fn m ->
        IO.inspect(indexing: m)
        res = {:tuple, [:ok, m]}

        [
          {:fun, :get, [{:symbol, m.name()}], res},
          {:fun, :get, [{:text, m.name()}], res}
        ]
      end)) ++
       [
         {:fun, :get, [{:var, :_}], {:tuple, [:error, :not_found]}}
       ]}
    |> Elementary.Ast.compiled()
  end

  defp module_name(p) when is_map(p) do
    module_name(p.name)
  end

  defp module_name(n) when is_binary(n) or is_atom(n) do
    Kit.camelize([n, "Playbook"])
  end

  defp playbooks(%{"playbooks" => playbooks}, _) do
    {:ok, playbooks}
  end

  defp playbooks(_, _) do
    {:ok, []}
  end

  defp steps(%{"steps" => steps}, providers) do
    Enum.reduce_while(steps, [], fn %{"title" => title} = s, acc ->
      {_, spec} = Map.split(s, ["title", "tags"])
      tags = tags(Map.get(s, "tags", []))

      case Kit.parse_spec(spec, providers) do
        {:ok, parsed} ->
          {:cont,
           [
             %Step{
               title: title,
               tags: tags,
               spec: parsed
             }
             | acc
           ]}

        {:error, _} = e ->
          {:halt, e}
      end
    end)
    |> case do
      {:error, _} = e ->
        e

      steps ->
        {:ok, Enum.reverse(steps)}
    end
  end

  defp steps(_, _) do
    {:ok, []}
  end

  defp tags(tags) when is_binary(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim(&1))
    |> tags()
  end

  defp tags(tags) when is_list(tags) do
    Enum.map(tags, &String.to_atom(&1))
  end
end
