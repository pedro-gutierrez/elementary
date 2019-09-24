defmodule Elementary.Lang.Encoders do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit

  defstruct spec: %{}

  def parse(%{"encoders" => spec}, providers) when is_map(spec) do
    case parse_encoders(spec, providers) do
      {:error, e} ->
        Kit.error(:parse_error, e)

      {:ok, encoders} ->
        {:ok, %__MODULE__{spec: encoders}}
    end
  end

  def parse(_, _) do
    {:ok, %__MODULE__{}}
  end

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
     |> Enum.map(fn {name, spec} ->
       spec.__struct__.ast(spec, index)
       |> encoder_fun_ast(name)
     end)) ++
      [
        not_implemented_ast()
      ]
  end

  def not_implemented_ast() do
    {:fun, :encode, [:_, :_], {:error, :not_implemented}}
  end

  defp encoder_fun_ast(ast, name) do
    {:fun, :encode, [{:text, name}, :_context], {:tuple, [:ok, ast]}}
  end
end
