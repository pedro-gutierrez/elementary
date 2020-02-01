defmodule Elementary.Encoder do
  @moduledoc false

  defguard is_literal(v) when is_binary(v) or is_number(v) or is_atom(v)

  def encode(spec, encoders \\ %{}) do
    encode(spec, %{}, encoders)
  end

  def encode(%{} = map, _, _) when map_size(map) == 0 do
    {:ok, map}
  end

  def encode(specs, context, encoders) when is_list(specs) do
    Enum.reduce_while(specs, [], fn spec, acc ->
      case encode(spec, context, encoders) do
        {:ok, encoded} ->
          {:cont, [encoded | acc]}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> result(specs, context)
  end

  def encode(nil = spec, context, _) do
    result({:error, :unsupported}, spec, context)
  end

  def encode("@" <> path = spec, context, _) do
    String.split(path, ".")
    |> Enum.reduce_while(context, fn
      key, map when is_map(map) ->
        case map[key] do
          nil ->
            {:error, %{"error" => "no_such_key", "key" => key, "data" => map}}

          value ->
            {:cont, value}
        end

      _, other ->
        {:halt, {:error, %{"error" => :not_a_map, "data" => other}}}
    end)
    |> result(spec, context)
  end

  def encode(v, _, _) when is_literal(v) do
    {:ok, v}
  end

  def encode(%{"dict" => dict} = spec, context, encoders) do
    Enum.reduce_while(dict, %{}, fn {key, spec}, acc ->
      case encode(spec, context, encoders) do
        {:ok, encoded} ->
          {:cont, Map.put(acc, key, encoded)}

        other ->
          {:halt, other}
      end
    end)
    |> result(spec, context)
  end

  def encode(%{"encoder" => encoder}, context, encoders) do
    case encoders[encoder] do
      spec when is_map(spec) ->
        encode(spec, context, encoders)

      nil ->
        {:error, %{"error" => "no_such_encoder", "encoder" => encoder, "data" => context}}
    end
  end

  def encode(%{"init" => init}, context, encoders) do
    encode_init(init, context, encoders)
  end

  def encode(spec, context, encoders) when is_map(spec) do
    encode(%{"dict" => spec}, context, encoders)
  end

  def encode_init(%{} = map, _, _) when map_size(map) == 0 do
    {:ok, map, []}
  end

  def not_supported(spec, context) do
    result({:error, :not_supported}, spec, context)
  end

  defp result({:error, e}, spec, context) do
    {:error, %{spec: spec, context: context, error: e}}
  end

  defp result(result, _, _), do: {:ok, result}
end
