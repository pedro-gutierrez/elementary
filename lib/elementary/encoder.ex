defmodule Elementary.Encoder do
  @moduledoc false

  defguard is_literal(v) when is_binary(v) or is_number(v) or is_atom(v)

  def encode(spec) do
    encode(spec, %{}, %{})
  end

  def encode(spec, context) do
    encode(spec, context, %{})
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

  def encode("@", context, _) do
    {:ok, context}
  end

  def encode("@" <> path = spec, context, _) do
    String.split(path, ".")
    |> Enum.reduce_while(context, fn
      key, map when is_map(map) ->
        case map[key] do
          nil ->
            {:halt, {:error, %{"error" => "no_such_key", "key" => key, "data" => map}}}

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

  def encode(%{"first" => expr} = spec, context, encoders) do
    with {:ok, encoded} <- encode(expr, context, encoders) do
      case encoded do
        [first | _] ->
          {:ok, first}

        other ->
          {:error, %{"error" => "unexpected", "actual" => other, "expected" => "non-empty-list"}}
      end
    end
    |> result(spec, context)
  end

  def encode(%{"equal" => exprs} = spec, context, encoders) do
    with {:ok, encoded} <- encode_all(exprs, context, encoders) do
      {:ok, all_equal?(encoded)}
    end
    |> result(spec, context)
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

  def encode(%{"url" => url_parts}, context, encoders) when is_list(url_parts) do
    Enum.reduce_while(url_parts, [], fn url_spec, parts ->
      case encode(url_spec, context, encoders) do
        {:ok, part} when is_binary(part) ->
          {:cont, [part | parts]}

        {:ok, other} ->
          {:halt, {:error, %{"error" => "unexpected", "actual" => other, "expected" => "binary"}}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:error, _} = error ->
        error

      parts ->
        {:ok, parts |> Enum.reverse() |> Enum.join("")}
    end
  end

  def encode(%{"url" => url_spec} = spec, context, encoders) do
    with {:ok, map} <- encode(url_spec, context, encoders) do
      "#{map["scheme"] || "http"}://#{map["host"] || "localhost"}:#{map["port"] || 80}#{
        map["path"] || ""
      }"
    end
    |> result(spec, context)
  end

  def encode(
        %{"http" => %{"url" => url_spec} = http_spec} = spec,
        context,
        encoders
      ) do
    with {:ok, url} <- encode(%{"url" => url_spec}, context, encoders),
         {:ok, method} <- maybe_encode(http_spec["method"], "get", context, encoders),
         {:ok, headers} <- maybe_encode(http_spec["headers"], nil, context, encoders),
         {:ok, body} <- maybe_encode(http_spec["body"], nil, context, encoders),
         {:ok, resp} =
           Elementary.Http.Client.run(
             debug: spec["debug"],
             method: method,
             url: url,
             body: body,
             headers: headers
           ) do
      case spec["as"] do
        nil ->
          {:ok, resp}

        name ->
          {:ok, %{name => resp}}
      end
    end
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

  def encode(%{"assert" => expr} = spec, context, encoders) do
    case encode(expr, context, encoders) do
      {:ok, true} ->
        {:ok, %{}}

      {:ok, other} ->
        {:error, %{"error" => "assert", "actual" => other, "expected" => true}}
    end
    |> result(spec, context)
  end

  def encode(%{"expect" => expr, "in" => key} = spec, context, encoders) do
    with {:ok, encoded} <- encode(key, context, encoders) do
      case Elementary.Decoder.decode(expr, encoded, context) do
        {:ok, _} ->
          {:ok, true}

        other ->
          {:error, %{"error" => "expect", "actual" => other, "expected" => expr}}
      end
    end
    |> result(spec, context)
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

  defp maybe_encode(nil, default, _, _), do: {:ok, default}

  defp maybe_encode(spec, _, context, encoders) do
    encode(spec, context, encoders)
  end

  defp encode_all(spec, context, encoders) do
    Enum.reduce_while(spec, [], fn expr, acc ->
      case encode(expr, context, encoders) do
        {:ok, encoded} ->
          {:cont, [encoded | acc]}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:error, _} = error ->
        error

      exprs ->
        {:ok, Enum.reverse(exprs)}
    end
  end

  defp all_equal?(exprs) when is_list(exprs) do
    1 ==
      exprs
      |> Enum.uniq()
      |> Enum.count()
  end

  def not_supported(spec, context) do
    result({:error, :not_supported}, spec, context)
  end

  defp result({:error, e}, spec, context) do
    {:error, %{spec: spec, context: context, error: e}}
  end

  defp result({:ok, _} = result, _, _), do: result
  defp result(result, _, _), do: {:ok, result}
end
