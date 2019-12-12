defmodule Elementary.Encoders do
  @moduledoc false

  use Elementary.Provider

  alias Elementary.Kit

  defstruct spec: %{}

  def default(), do: %__MODULE__{}

  def parse(%{"encoders" => spec}, providers) when is_map(spec) do
    case parse_encoders(spec, providers) do
      {:error, e} ->
        Kit.error(:parse_error, e)

      {:ok, encoders} ->
        {:ok, %__MODULE__{spec: encoders}}
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  defp parse_encoders(encoders, providers) do
    encoders
    |> Enum.reduce_while(%{}, fn {name, spec}, by_name ->
      case spec |> Kit.parse_spec(providers) do
        {:ok, parsed} ->
          {:cont, Map.put(by_name, name, parsed)}

        {:error, _} = e ->
          {:halt, e}
      end
    end)
    |> case do
      {:error, _} = e ->
        e

      parsed ->
        {:ok, parsed}
    end
  end

  def ast(%{spec: names}, index) do
    (names
     |> Enum.flat_map(fn {name, spec} ->
       spec.__struct__.ast(spec, index)
       |> encoder_fun_ast(name)
     end)) ++
      [
        not_implemented_ast()
      ]
  end

  def not_implemented_ast() do
    {:fun, :encode, [:encoder, :_data],
     {:error,
      {:map,
       [
         {:error, :no_encoder},
         {:data, {:var, :encoder}}
       ]}}}
  end

  defp encoder_fun_ast(ast, name) do
    data_var = Elementary.Ast.fn_clause_var_name(ast, :data)

    [
      {:fun, :encode, [{:symbol, name}, data_var], ast},
      {:fun, :encode, [name, data_var], ast}
    ]
  end
end
