defmodule Elementary.List do
  @moduledoc false

  use Elementary.Provider,
    kind: "list",
    module: __MODULE__

  alias Elementary.Kit

  defstruct spec: []

  def parse(specs, providers) when is_list(specs) do
    case Enum.reduce_while(specs, [], fn spec, acc ->
           case Kit.parse_spec(spec, providers) do
             {:ok, parsed} ->
               {:cont, [parsed | acc]}

             {:error, _} = e ->
               {:halt, e}
           end
         end) do
      {:error, e} ->
        Kit.error(:parse_error, e)

      items ->
        {:ok, %__MODULE__{spec: items |> Enum.reverse()}}
    end
  end

  def parse(%{"list" => "empty"}, _) do
    {:ok, %__MODULE__{spec: :empty}}
  end

  def parse(%{"list" => spec}, providers) do
    parse(spec, providers)
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def ast(%__MODULE__{spec: :empty}, _) do
    {:ok, {:list, []}}
  end

  def ast(spec, index) do
    spec |> split() |> ast_from_split_specs(index)
  end

  defp ast_from_split_specs({literals, []}, index) do
    {:ok, {:list, literal_ast_entries(literals, index)}}
  end

  defp ast_from_split_specs({literals, exprs}, index) do
    {:let, generators_ast(exprs, index),
     {:ok, {:list, return_ast(exprs) ++ literal_ast_entries(literals, index)}}}
  end

  def generators_ast(exprs, index, prefix \\ "v") do
    {_, asts} =
      exprs
      |> Enum.reduce({0, []}, fn item, {idx, gens} ->
        {idx + 1,
         [{"#{prefix}#{idx}" |> String.to_atom(), item.__struct__.ast(item, index)} | gens]}
      end)

    asts
  end

  def return_ast(exprs, prefix \\ "v") do
    {_, asts} =
      exprs
      |> Enum.reduce({0, []}, fn _, {idx, vars} ->
        {idx + 1, [{:var, "#{prefix}#{idx}"} | vars]}
      end)

    asts
  end

  defp literal_ast_entries(literals, index) do
    Enum.map(literals, fn item ->
      {:ok, ast} = item.__struct__.ast(item, index)
      ast
    end)
  end

  def decoder_ast(%{spec: :empty}, lv) do
    {{:list, []}, [], [], lv}
  end

  defp split(parsed) do
    {literals, exprs} =
      Enum.reduce(parsed.spec, {[], []}, fn item, {literals, expressions} ->
        case item.__struct__.literal?(item) do
          true ->
            {[item | literals], expressions}

          false ->
            {literals, [item | expressions]}
        end
      end)

    {Enum.reverse(literals), Enum.reverse(exprs)}
  end

  def literal?(%__MODULE__{} = parsed) do
    literal?(parsed.spec)
  end

  def literal?(:empty), do: true

  def literal?(items) when is_list(items) do
    Enum.reduce_while(items, true, fn i, _ ->
      case i.__struct__.literal?(i) do
        false ->
          {:halt, false}

        true ->
          {:cont, true}
      end
    end)
  end
end
