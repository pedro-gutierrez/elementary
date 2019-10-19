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
      Enum.filter(playbook.steps, fn s ->
        true
        # s.spec.__struct__ == Elementary.Steps
      end)
      |> Enum.flat_map(fn s ->
        [{:fun, :run, [{:text, s.title}, :_data], {:tuple, [:ok, {:text, s.title}]}}] ++
          Enum.map(s.tags, fn t ->
            {:fun, :run, [{:symbol, t}, :data], {:call, :run, [{:text, s.title}, {:var, :data}]}}
          end)
      end)

    default_run_ast = [{:fun, :run, [{:var, :_name}, :_data], {:tuple, [:error, :not_found]}}]

    [
      {:module, test_module_name(playbook),
       [
         {:fun, :kind, [], :playbook},
         {:fun, :name, [], {:symbol, playbook.name}}
       ] ++ run_asts ++ default_run_ast}
    ]
  end

  defp test_module_name(test) do
    Kit.camelize([test.name, "Playbook"])
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
