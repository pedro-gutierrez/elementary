defmodule Elementary.Decoder do
  @moduledoc false

  defguard is_literal(v) when is_binary(v) or is_number(v) or is_atom(v)

  def decode(nil, nil, _) do
    {:ok, nil}
  end

  def decode(nil = spec, data, _) do
    decode_error(spec, data)
  end

  def decode(%{"any" => "text"} = spec, data, _) when is_binary(data) do
    case String.valid?(data) do
      true ->
        {:ok, data}

      false ->
        decode_error(spec, data)
    end
  end

  def decode(%{"any" => "date"} = spec, data, _) when is_binary(data) do
    case DateTime.from_iso8601(data) do
      {:error, _} ->
        decode_error(spec, data)

      {:ok, datetime, _offset} ->
        {:ok, datetime}
    end
  end

  def decode(%{"any" => "data"} = spec, data, _) when is_binary(data) do
    case String.valid?(data) do
      true ->
        decode_error(spec, data)

      false ->
        {:ok, data}
    end
  end

  def decode(v, v, _) when is_literal(v) do
    {:ok, v}
  end

  def decode(spec, data, _) when is_literal(spec) do
    decode_error(spec, data)
  end

  def decode(spec, data, context) when is_map(spec) do
    decode_dict(spec, data, context)
  end

  def decode(spec, data, _) do
    decode_error(spec, data)
  end

  defp result({:error, _} = other, _) do
    other
  end

  defp result(decoded, _) do
    {:ok, decoded}
  end

  defp decode_error(spec, data) do
    {:error, %{error: :decode, spec: spec, data: data}}
  end

  defp decode_dict(spec, data, context) when is_map(data) do
    Enum.reduce_while(spec, %{}, fn {key, spec}, acc ->
      case decode(spec, data[key], context) do
        {:ok, decoded} ->
          {:cont, Map.put(acc, key, decoded)}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> result(data)
  end

  defp decode_dict(spec, data, _) do
    decode_error(spec, data)
  end
end
