defmodule Elementary.Decoder do
  @moduledoc false

  require Logger

  import Elementary.Encoder, only: [encode: 2]

  defguard is_literal(v) when is_binary(v) or is_number(v) or is_atom(v)

  def decode(nil, nil, _) do
    {:ok, nil}
  end

  def decode(nil = spec, data, _) do
    decode_error(spec, data)
  end

  def decode(data, data, _), do: {:ok, data}

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

  def decode(%{"any" => "float"}, data, _) when is_float(data) do
    {:ok, data}
  end

  def decode(%{"any" => "float"} = spec, data, context) when is_binary(data) do
    with {:ok, encoded} <- Elementary.Encoder.encode(data, context),
         {decoded, ""} <- Float.parse(encoded) do
      {:ok, decoded}
    end
    |> result(spec)
  end

  def decode(%{"any" => "int"}, data, _) when is_integer(data) do
    {:ok, data}
  end

  def decode(%{"any" => "int"} = spec, data, context) when is_binary(data) do
    with {:ok, encoded} <- Elementary.Encoder.encode(data, context),
         {decoded, ""} <- Integer.parse(encoded) do
      {:ok, decoded}
    end
    |> result(spec)
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
    with {:ok, date, _} <- DateTime.from_iso8601(data) do
      {:ok, date}
    end
    |> result(spec)
  end

  def decode(%{"any" => "date"}, %DateTime{} = data, _) do
    {:ok, data}
  end

  def decode(%{"any" => "data"} = spec, data, _) when is_binary(data) do
    case String.valid?(data) do
      true ->
        decode_error(spec, data)

      false ->
        {:ok, data}
    end
  end

  def decode(%{"text" => transforms} = spec, data, context)
      when is_binary(data) and byte_size(data) > 0 do
    Enum.reduce_while(transforms, nil, fn encoder, _ ->
      case encode(%{encoder => data}, context) do
        {:ok, encoded} ->
          {:cont, encoded}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
    |> case do
      nil ->
        decode_error(spec, data)

      {:error, _} ->
        decode_error(spec, data)

      decoded ->
        {:ok, decoded}
    end
  end

  def decode(%{"empty" => "list"}, [], _) do
    {:ok, []}
  end

  def decode(%{"non_empty" => "list"}, [_ | _] = data, _) do
    {:ok, data}
  end

  def decode(%{"list" => %{"size" => size}} = spec, data, context) when is_list(data) do
    with {:ok, size} <- encode(size, context) do
      case length(data) == size do
        true ->
          {:ok, data}

        false ->
          decode_error(spec, data)
      end
    end
    |> result(spec)
  end

  def decode(%{"list" => %{"with" => dec}} = spec, data, context) when is_list(data) do
    with {:ok, dec} <- encode(dec, context) do
      Enum.reduce_while(data, [], fn item, acc ->
        case decode(dec, item, context) do
          {:ok, decoded} ->
            {:cont, [decoded | acc]}

          {:error, _} ->
            {:cont, acc}
        end
      end)
      |> case do
        [] -> {:error, %{"error" => "none_matched", "data" => data, "spec" => dec}}
        decoded -> {:ok, Enum.reverse(decoded)}
      end
    end
    |> result(spec)
  end

  def decode(%{"list" => %{"without" => dec}} = spec, data, context) when is_list(data) do
    with {:ok, dec} <- encode(dec, context),
         nil <-
           Enum.reduce_while(data, nil, fn item, _ ->
             case decode(dec, item, context) do
               {:error, _} ->
                 {:cont, nil}

               {:ok, _} ->
                 {:halt, {:error, %{"error" => "some_matched", "data" => item}}}
             end
           end) do
      {:ok, data}
    end
    |> result(spec)
  end

  def decode(%{"first" => %{"with" => dec}} = spec, data, context) when is_list(data) do
    with {:ok, dec} <- encode(dec, context) do
      Enum.reduce_while(data, nil, fn item, _ ->
        case decode(dec, item, context) do
          {:ok, decoded} ->
            {:halt, decoded}

          {:error, _} ->
            {:cont, nil}
        end
      end)
      |> case do
        nil ->
          case spec["otherwise"] do
            nil ->
              {:error, %{"error" => "none_matched", "data" => data, "spec" => dec}}

            default ->
              encode(default, context)
          end

        decoded ->
          {:ok, decoded}
      end
    end
    |> result(spec)
  end

  def decode(%{"list" => dec} = spec, data, context) when is_list(data) do
    with {:ok, dec} <- encode(dec, context),
         nil <-
           Enum.reduce_while(data, nil, fn item, _ ->
             case decode(dec, item, context) do
               {:ok, _} ->
                 {:cont, nil}

               {:error, _} = err ->
                 {:halt, err}
             end
           end) do
      {:ok, data}
    end
    |> result(spec)
  end

  def decode(%{"one_of" => decs} = spec, data, context) do
    with {:ok, decs} <- encode(decs, context),
         nil <-
           Enum.reduce_while(decs, {:error, %{"error" => "none_matched", "data" => data}}, fn dec,
                                                                                              _ ->
             case decode(dec, data, context) do
               {:ok, _} ->
                 {:halt, nil}

               {:error, _} = err ->
                 {:cont, err}
             end
           end) do
      {:ok, data}
    end
    |> result(spec)
  end

  def decode(%{"other_than" => value} = spec, data, context) do
    with {:ok, ^data} <- encode(value, context) do
      decode_error(spec, data)
    end
    |> result(spec)
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

  def decode(%{"with_pair" => [key_spec, value_spec], "in" => target} = spec, data, context) do
    with {:ok, target} <- Elementary.Encoder.encode(target, context),
         {:ok, key} <- Elementary.Encoder.encode(key_spec, context),
         {:ok, value} <- Elementary.Encoder.encode(value_spec, context),
         {:ok, key} <- Elementary.Encoder.encode("@" <> key, data, context),
         {:ok, value} <- Elementary.Encoder.encode("@" <> value, data, context) do
      case target[key] do
        ^value ->
          {:ok, data}

        _ ->
          decode_error(spec, data)
      end
    end
    |> result(spec)
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

  def decode(%{"before" => value} = spec, data, context) do
    with {:ok, d2} <- encode(value, context),
         {:ok, d1} <- decode(%{"any" => "date"}, data, context) do
      case DateTime.compare(d1, d2) do
        :lt ->
          {:ok, d1}

        _ ->
          decode_error(spec, data)
      end
    end
    |> result(spec)
  end

  def decode(%{"after" => value} = spec, data, context) do
    with {:ok, d2} <- encode(value, context),
         {:ok, d1} <- decode(%{"any" => "date"}, data, context) do
      case DateTime.compare(d1, d2) do
        :gt ->
          {:ok, d1}

        _ ->
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

  defp result({:ok, _} = decoded, _) do
    decoded
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
