defmodule Elementary.Spec do
  @moduledoc false

  alias Elementary.Kit

  def files() do
    Path.wildcard(Kit.home() <> "/**/*.yml")
  end

  def all() do
    files()
    |> Enum.map(fn yaml ->
      case Kit.read_yaml(yaml) do
        {:ok, content} ->
          content = Map.put(content, "source", yaml)
          Map.put_new(content, "version", "1")

        {:error, e} ->
          raise "Error reading YAML: #{yaml}: #{inspect(e)}"
      end
    end)
    |> Enum.reduce(%{}, fn spec, index ->
      put(index, spec)
    end)
  end

  def find(specs, kind, name) do
    with {:ok, specs} <- Map.fetch(specs, kind),
         {:ok, _} = result <- Map.fetch(specs, name) do
      result
    else
      _ ->
        :not_found
    end
  end

  def find!(index, kind, name) do
    case find(index, kind, name) do
      {:ok, spec} ->
        spec

      :not_found ->
        raise "No spec of kind \"#{kind}\" and name: \"#{name}\", in #{
                inspect(names(index, kind))
              }"
    end
  end

  def put(specs, %{"kind" => kind, "name" => name} = spec) do
    specs_for_kind =
      specs
      |> Map.get(kind, %{})
      |> Map.put(name, spec)

    Map.put(specs, kind, specs_for_kind)
  end

  def all(specs, kind) do
    case Map.fetch(specs, kind) do
      {:ok, specs} ->
        specs

      :error ->
        %{}
    end
  end

  def names(specs, kind) do
    case Map.fetch(specs, kind) do
      {:ok, specs} ->
        Map.keys(specs)

      :error ->
        []
    end
  end

  def flatten(specs) do
    Enum.flat_map(specs, fn {_, specs} ->
      Map.values(specs)
    end)
  end

  def merge(specs) do
    Enum.reduce(specs, %{}, fn map, acc ->
      merge(acc, map)
    end)
  end

  def merge(map1, map2) when is_map(map1) and is_map(map2) do
    Enum.reduce(map2, map1, fn {key, value}, map1 ->
      case Map.get(map1, key, :undefined) do
        :undefined ->
          Map.put(map1, key, value)

        existing ->
          value = merge(existing, value)
          Map.put(map1, key, value)
      end
    end)
  end

  def merge(list1, list2) when is_list(list1) and is_list(list2) do
    list1 ++ list2
  end

  def merge(value1, _), do: value1
end
