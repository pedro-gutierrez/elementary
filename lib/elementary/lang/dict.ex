defmodule Elementary.Lang.Dict do
  @moduledoc false

  use Elementary.Provider,
    rank: :low

  alias Elementary.Kit

  defstruct spec: %{}

  def default(), do: %__MODULE__{}

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

  def parse(spec, providers) when is_map(spec) do
    parse(%{"dict" => spec}, providers)
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def ast(dict, index) do
    {:dict,
     Enum.map(dict.spec, fn {k, v} ->
       ast = v.__struct__.ast(v, index)

       case v.__struct__.literal?(v) do
         true ->
           {:literal, k,
            case ast do
              {:ok, v} ->
                v

              v ->
                v
            end}

         false ->
           {:expression, k, ast}
       end
     end)}
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
