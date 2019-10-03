defmodule Elementary.Lang.Dict do
  @moduledoc false

  use Elementary.Provider,
    kind: "dict",
    module: __MODULE__

  alias Elementary.Kit

  defstruct spec: %{}

  def parse(%{"dict" => "any"}, _) do
    {:ok, %__MODULE__{spec: :any}}
  end

  def parse(%{"dict" => spec} = dict, providers) when is_map(spec) do
    case Enum.reduce_while(spec, %{}, fn {k, v}, acc ->
           case Kit.parse_spec(v, providers) do
             {:ok, parsed} ->
               {:cont, Map.put(acc, k, parsed)}

             {:error, e} ->
               {:halt, {:error, e}}
           end
         end) do
      {:error, e} ->
        Kit.error(:parse_error, %{
          spec: dict,
          reason: e
        })

      dict ->
        {:ok, %__MODULE__{spec: dict}}
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def ast(dict, index) do
    dict |> split() |> ast_from_split_specs(index)
  end

  def generators_ast(exprs, index, prefix \\ "v") do
    {_, asts} =
      exprs
      |> Enum.reduce({0, []}, fn {_, v}, {idx, gens} ->
        {idx + 1, [{"#{prefix}#{idx}" |> String.to_atom(), v.__struct__.ast(v, index)} | gens]}
      end)

    asts
  end

  def return_ast(exprs, prefix \\ "v") do
    {_, asts} =
      exprs
      |> Enum.reduce({0, []}, fn {k, _}, {idx, entries} ->
        {idx + 1, [{k, {:var, "#{prefix}#{idx}"}} | entries]}
      end)

    asts
  end

  defp ast_from_split_specs({[], []}, _) do
    :empty_map
  end

  defp ast_from_split_specs({literals, []}, index) do
    {:ok, {:map, literal_ast_entries(literals, index)}}
  end

  defp ast_from_split_specs({literals, exprs}, index) do
    {:let, generators_ast(exprs, index),
     {:map, return_ast(exprs) ++ literal_ast_entries(literals, index)}}
  end

  defp literal_ast_entries(literals, index) do
    Enum.map(literals, fn {k, v} ->
      {:ok, v} = v.__struct__.ast(v, index)
      {k, v}
    end)
  end

  def decoder_ast(%{spec: spec}, lv) when is_map(spec) do
    {pattern, guards, data, lv} =
      spec
      |> Enum.reduce({[], [], [], lv}, fn {k, v}, {p, g, d, lv} ->
        {p0, g0, d0, lv} = v.__struct__.decoder_ast(v, lv)
        {[{{:text, k}, p0} | p], g0 ++ g, [{{:text, k}, d0} | d], lv}
      end)

    {{:map, pattern}, guards, {:map, data}, lv}
  end

  defp split(parsed) do
    parsed.spec
    |> Enum.reduce({[], []}, fn {k, v}, {literals, expressions} ->
      case v.__struct__.literal?(v) do
        true ->
          {[{k, v} | literals], expressions}

        false ->
          {literals, [{k, v} | expressions]}
      end
    end)
  end

  def literal?(parsed) do
    Enum.reduce_while(parsed.spec, true, fn {_, v}, _ ->
      case v.__struct__.literal?(v) do
        false ->
          {:halt, false}

        true ->
          {:cont, true}
      end
    end)
  end
end
