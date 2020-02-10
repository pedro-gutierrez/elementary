defmodule Elementary.Decoder do
  @moduledoc false

  defguard is_literal(v) when is_binary(v) or is_number(v) or is_atom(v)

  def decode(nil, nil, _) do
    {:ok, nil}
  end

  def decode(nil = spec, data, _) do
    decode_error(spec, data)
  end

  def decode(spec, data, context) when is_binary(spec) do
    case Elementary.Encoder.encode(spec, context) do
      {:ok, ^data} ->
        {:ok, data}

      _ ->
        decode_error(spec, data)
    end
  end

  def decode(%{"any" => "text"} = spec, data, _) when is_binary(data) do
    case String.valid?(data) do
      true ->
        {:ok, data}

      false ->
        decode_error(spec, data)
    end
  end

  def decode(%{"any" => "number"}, data, _) when is_number(data) do
    {:ok, data}
  end

  def decode(%{"any" => "list"}, data, _) when is_list(data) do
    {:ok, data}
  end

  def decode(%{"any" => "object"}, data, _) when is_map(data) do
    {:ok, data}
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

  def decode(%{"without" => keys} = spec, data, context) when is_map(data) do
    with {:ok, keys} <- Elementary.Encoder.encode(keys, context) do
      Enum.reduce_while(keys, :ok, fn key, _ ->
        case data[key] do
          nil ->
            {:cont, :ok}

          other ->
            {:halt, {:error, %{"unexpected" => key, "value" => other, "in" => data}}}
        end
      end)
      |> case do
        :ok ->
          {:ok, data}

        _ ->
          decode_error(spec, data)
      end
    end
    |> result(spec)
  end

  def decode(%{"not" => expr} = spec, data, context) do
    case decode(expr, data, context) do
      {:ok, _} ->
        decode_error(spec, data)

      {:error, %{error: :decode}} ->
        {:ok, data}

      {:error, _} = err ->
        err
    end
  end

  def decode(%{"in" => items} = spec, data, context) do
    with {:ok, items} <- Elementary.Encoder.encode(items, context) do
      case Enum.member?(items, data) do
        true ->
          {:ok, data}

        false ->
          decode_error(spec, data)
      end
    end
    |> result(spec)
  end

  def decode(%{"less_than" => value} = spec, data, context) when is_number(data) do
    with {:ok, encoded} when is_number(encoded) <-
           Elementary.Encoder.encode(value, context) do
      case data < encoded do
        true ->
          {:ok, data}

        false ->
          decode_error(spec, data)
      end
    end
    |> result(spec)
  end

  def decode(%{"greater_than" => value} = spec, data, context) when is_number(data) do
    with {:ok, encoded} when is_number(encoded) <-
           Elementary.Encoder.encode(value, context) do
      case data > encoded do
        true ->
          {:ok, data}

        false ->
          decode_error(spec, data)
      end
    end
    |> result(spec)
  end

  def decode(v, v, _) when is_literal(v) do
    {:ok, v}
  end

  def decode(spec, data, _) when is_literal(spec) do
    decode_error(spec, data)
  end

  def decode(spec, data, context) when is_map(spec) do
    decode_object(spec, data, context)
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

  defp decode_object(spec, data, context) when is_map(data) do
    Enum.reduce_while(spec, %{}, fn {key, spec}, acc ->
      with {:ok, decoded} <- decode(spec, data[key], context) do
        {:cont, Map.put(acc, key, decoded)}
      else
        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> result(data)
  end

  defp decode_object(spec, data, _) do
    decode_error(spec, data)
  end
end
