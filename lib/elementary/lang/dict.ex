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
    {:map,
     Enum.map(dict.spec, fn {k, v} ->
       {k, v.__struct__.ast(v, index)}
     end)}
  end

  def decoder_ast(%{spec: spec}, level) when is_map(spec) do
    {pattern, guards, data} =
      spec
      |> Enum.reduce({[], [], []}, fn {k, v}, {p, g, d} ->
        {p0, g0, d0} = v.__struct__.decoder_ast(v, level + 1)
        {[{{:text, k}, p0} | p], g0 ++ g, [{{:text, k}, d0} | d]}
      end)

    {{:map, pattern}, guards, {:map, data}}
  end
end
