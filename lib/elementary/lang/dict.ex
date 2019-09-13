defmodule Elementary.Lang.Dict do
  @moduledoc false

  use Elementary.Provider,
    kind: "dict",
    module: __MODULE__

  alias Elementary.Kit

  defstruct [
    spec: %{}
  ]

  def parse(%{ "dict" => spec} = dict, providers) do
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

  def compile(dict, providers) do
    [
      """
      %{
        #{ dict.spec |> Enum.map(fn {k, v} ->
          "\"#{k}\" => #{ v.__struct__.compile(v,providers) }"
        end) |> Enum.join(",") }
      }
      """
    ]
  end

  def ast(dict, index) do
    {:map, Enum.map(dict.spec, fn {k, v} ->
      {k, v.__struct__.ast(v, index)}
    end)}
  end

end
