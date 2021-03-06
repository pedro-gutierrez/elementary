defmodule Elementary.Encoder do
  @moduledoc false

  alias Elementary.Decoder

  defguard is_literal(v) when is_binary(v) or is_number(v) or is_atom(v)

  def encode!(spec) do
    case encode(spec) do
      {:ok, encoded} ->
        encoded

      other ->
        raise "Could not encode #{inspect(spec)}: #{inspect(other)}"
    end
  end

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
    |> case do
      {:error, _} = err ->
        err

      items ->
        {:ok, Enum.reverse(items)}
    end
    |> result(specs, context)
  end

  def encode(nil, _, _) do
    {:ok, nil}
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
            {:halt, {:error, %{"error" => "no_such_key", "key" => key, "keys" => Map.keys(map)}}}

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

  @dates [NaiveDateTime, DateTime]

  def encode(%{__struct__: struct} = date, _, _) when struct in @dates, do: {:ok, date}

  def encode(%{"resolve" => items} = spec, context, encoders) do
    with {:ok, [first | rest] = items} when is_list(items) <- encode(items, context, encoders) do
      Enum.reduce_while(rest, first, fn item, current ->
        case encode("@#{item}", current, encoders) do
          {:ok, current} ->
            {:cont, current}

          {:error, _} = e ->
            {:halt, e}
        end
      end)
    end
    |> result(spec, context)
  end

  def encode(%{"object" => object} = spec, context, encoders) do
    Enum.reduce_while(object, %{}, fn {key, spec}, acc ->
      case encode(spec, context, encoders) do
        {:ok, encoded} ->
          {:cont, Map.put(acc, key, encoded)}

        other ->
          {:halt, other}
      end
    end)
    |> result(spec, context)
  end

  def encode(%{"maybe" => path} = spec, context, encoders) do
    case encode(path, context, encoders) do
      {:ok, _} = res ->
        res

      {:error, e} ->
        if spec["debug"] do
          IO.inspect(%{"spec" => spec, "error" => e})
        end

        encode(spec["otherwise"] || "", context, encoders)
    end
    |> result(spec, context)
  end

  def encode(%{"oneOf" => exprs} = spec, context, encoders) when is_list(exprs) do
    Enum.reduce_while(exprs, false, fn expr, _ ->
      case encode(expr, context, encoders) do
        {:ok, false} ->
          {:cont, false}

        {:ok, _} ->
          {:halt, true}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
    |> result(spec, context)
  end

  def encode(%{"either" => clauses} = spec, context, encoders) do
    with nil <-
           Enum.reduce_while(clauses, nil, fn clause, _ ->
             case encode(clause, context, encoders) do
               {:ok, _} = res ->
                 {:halt, res}

               {:error, _} ->
                 {:cont, nil}
             end
           end) do
      {:error, %{"error" => "no_clause_applies", "spec" => spec}}
    end
    |> result(spec, context)
  end

  def encode(%{"when" => condition, "then" => then} = spec, context, encoders) do
    case encode(condition, context, encoders) do
      {:ok, false} ->
        {:error, :failed_condition}

      {:ok, _} ->
        encode(then, context, encoders)
    end
    |> result(spec, context)
  end

  def encode(%{"when" => condition} = spec, context, encoders) do
    case encode(condition, context, encoders) do
      {:ok, true} ->
        encode(Map.drop(spec, ["when"]), context, encoders)

      {:ok, false} ->
        {:error, :failed_condition}
    end
    |> result(spec, context)
  end

  def encode(%{"map" => expr, "with" => encoder} = spec, context, encoders) do
    with {:ok, data} <- encode(expr, context, encoders) do
      case data do
        [] ->
          {:ok, []}

        [_ | _] ->
          data =
            case spec["as"] do
              nil ->
                Enum.map(data, fn item -> Map.merge(context, item) end)

              as ->
                Enum.map(data, fn item -> Map.merge(context, %{as => item}) end)
            end

          encode_items(encoder, data, encoders)

        other ->
          {:error, %{"error" => "not_a_list", "data" => other}}
      end
    end
    |> result(spec, context)
  end

  def encode(%{"filter" => expr, "with" => encoder} = spec, context, encoders) do
    with {:ok, data} when is_list(data) <- encode(expr, context, encoders),
         {:ok, as} <- encode(spec["as"] || "item", context, encoders) do
      Enum.reduce_while(data, [], fn item, acc ->
        item_ctx = Map.merge(context, %{as => item})

        case encode(encoder, item_ctx, encoders) do
          {:ok, true} ->
            {:cont, [item | acc]}

          {:ok, false} ->
            {:cont, acc}

          {:error, e} ->
            {:halt, e}
        end
      end)
      |> case do
        {:error, _} = e ->
          e

        filtered ->
          {:ok, Enum.reverse(filtered)}
      end
    end
    |> result(spec, context)
  end

  def encode(%{"distinct" => items} = spec, context, encoders) do
    case encode(items, context, encoders) do
      {:ok, items} when is_list(items) ->
        {:ok, Enum.uniq(items)}

      {:ok, items} ->
        {:error, %{"error" => "wrong_type", "expected" => "list", "actual" => items}}

      {:error, _} = error ->
        error
    end
    |> result(spec, context)
  end

  def encode(%{"reduce" => source, "initial" => initial, "with" => fun} = spec, context, encoders) do
    with {:ok, source} when is_list(source) <- encode(source, context, encoders),
         {:ok, initial} <- encode(initial, context, encoders) do
      Enum.reduce_while(source, {:ok, initial}, fn item, {:ok, acc} ->
        case encode(fun, %{"item" => item, "acc" => acc, "model" => context}, encoders) do
          {:ok, _} = value ->
            {:cont, value}

          {:error, _} = err ->
            {:halt, err}
        end
      end)
    end
    |> result(spec, context)
  end

  def encode(%{"let" => vars, "in" => expr} = spec, context, encoders) do
    with {:ok, vars} <- encode(vars, context, encoders) do
      encode(expr, Map.merge(context, vars), encoders)
    end
    |> result(spec, context)
  end

  def encode(%{"merge" => items} = spec, context, encoders) do
    case encode(items, context, encoders) do
      {:ok, []} ->
        {:ok, []}

      {:ok, [first | _] = items} when is_map(first) ->
        {:ok,
         Enum.reduce(items, %{}, fn item, acc ->
           Map.merge(acc, item)
         end)}

      {:ok, [first | _] = items} when is_list(first) ->
        {:ok,
         Enum.reduce(items, [], fn item, acc ->
           acc ++ item
         end)}

      {:ok, other} ->
        {:error, %{"error" => "unexpected", "data" => other, "expected" => "all_maps|all_lists"}}

      {:error, _} = error ->
        error
    end
    |> result(spec, context)
  end

  def encode(%{"drop" => keys, "from" => expr} = spec, context, encoders) do
    with {:ok, keys} when is_list(keys) <- encode(keys, context, encoders),
         {:ok, map} when is_map(map) <- encode(expr, context, encoders) do
      {:ok, Map.drop(map, keys)}
    end
    |> result(spec, context)
  end

  def encode(%{"first" => expr} = spec, context, encoders) do
    with {:ok, encoded} <- encode(expr, context, encoders) do
      case encoded do
        [first | _] ->
          {:ok, first}

        other ->
          {:error,
           %{
             "error" => "unexpected",
             "actual" => other,
             "expected" => "non-empty-list",
             "spec" => spec,
             "context" => context
           }}
      end
    end
    |> result(spec, context)
  end

  def encode(%{"last" => expr} = spec, context, encoders) do
    with {:ok, encoded} <- encode(expr, context, encoders) do
      case is_list(encoded) && length(encoded) > 0 do
        true ->
          {:ok, List.last(encoded)}

        false ->
          {:error,
           %{"error" => "unexpected", "actual" => encoded, "expected" => "non-empty-list"}}
      end
    end
    |> result(spec, context)
  end

  def encode(%{"join" => items, "using" => sep} = spec, context, encoders) do
    with {:ok, items} <- encode(items, context, encoders),
         {:ok, sep} <- encode(sep, context, encoders) do
      {:ok, Enum.join(items, sep)}
    end
    |> result(spec, context)
  end

  def encode(%{"split" => expr, "using" => sep} = spec, context, encoders) do
    with {:ok, expr} <- encode(expr, context, encoders),
         {:ok, sep} <- encode(sep, context, encoders) do
      {:ok, String.split(expr, sep)}
    end
    |> result(spec, context)
  end

  def encode(%{"item" => index, "in" => items} = spec, context, encoders) do
    with {:ok, index} <- encode(index, context, encoders),
         {:ok, items} <- encode(items, context, encoders) do
      Enum.fetch(items, index)
    end
    |> result(spec, context)
  end

  def encode(%{"member" => member, "of" => col} = spec, context, encoders) do
    with {:ok, member} <- encode(member, context, encoders),
         {:ok, col} <- encode(col, context, encoders) do
      {:ok, Enum.member?(col, member)}
    end
    |> result(spec, context)
  end

  def encode(%{"equal" => exprs} = spec, context, encoders) do
    with {:ok, encoded} <- encode_specs(exprs, context, encoders) do
      {:ok, all_equal?(encoded)}
    end
    |> result(spec, context)
  end

  def encode(%{"intFrom" => str} = spec, context, encoders) do
    with {:ok, str} <- encode(str, context, encoders),
         {int, ""} <- Integer.parse(str) do
      {:ok, int}
    end
    |> result(spec, context)
  end

  def encode(%{"atLeast" => exprs} = spec, context, encoders) do
    with {:ok, [num1, num2]} when is_number(num1) and is_number(num2) <-
           encode_specs(exprs, context, encoders) do
      {:ok, num1 >= num2}
    end
    |> result(spec, context)
  end

  def encode(%{"lessThan" => exprs} = spec, context, encoders) do
    with {:ok, [num1, num2]} when is_number(num1) and is_number(num2) <-
           encode_specs(exprs, context, encoders) do
      {:ok, num1 < num2}
    end
    |> result(spec, context)
  end

  def encode(
        %{"switch" => expr, "case" => clauses, "default" => default} = spec,
        context,
        encoders
      ) do
    with {:ok, expr} <- encode(expr, context, encoders),
         {:ok, clauses} when is_map(clauses) <- encode(clauses, context, encoders),
         {:ok, default} <- encode(default, context, encoders) do
      case clauses[expr] do
        nil ->
          {:ok, default}

        value ->
          {:ok, value}
      end
    end
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

  def encode(
        %{"uri" => uri, "with" => query} = spec,
        context,
        encoders
      ) do
    with {:ok, uri} <- encode(uri, context, encoders),
         {:ok, query} <- encode(query, context, encoders) do
      {:ok, "#{uri}?#{URI.encode_query(query)}"}
    end
    |> result(spec, context)
  end

  def encode(%{"uuid" => _}, _, _) do
    {:ok, UUID.uuid4()}
  end

  def encode(%{"sum" => items} = spec, context, encoders) do
    with {:ok, encoded} <- encode_specs(items, context, encoders) do
      Enum.reduce_while(encoded, 0, fn
        item, acc when is_number(item) ->
          {:cont, acc + item}

        other, _ ->
          {:halt,
           {:error, %{"error" => "not_a_number", "actual" => other, "expected" => "number"}}}
      end)
    end
    |> result(spec, context)
  end

  def encode(%{"diff" => items} = spec, context, encoders) do
    with {:ok, items} <- encode_specs(items, context, encoders) do
      case items do
        [] ->
          {:ok, 0}

        [first | rest] when is_number(first) ->
          Enum.reduce_while(rest, first, fn
            item, acc when is_number(item) ->
              {:cont, acc - item}

            other, _ ->
              {:halt,
               {:error, %{"error" => "not_a_number", "actual" => other, "expected" => "number"}}}
          end)
      end
    end
    |> result(spec, context)
  end

  def encode(%{"firstDay" => date} = spec, context, encoders) do
    with {:ok, date} <- encode(date, context, encoders) do
      Elementary.Calendar.first_dom(date)
    end
    |> result(spec, context)
  end

  def encode(%{"lastDay" => date} = spec, context, encoders) do
    with {:ok, date} <- encode(date, context, encoders) do
      Elementary.Calendar.last_dom(date)
    end
    |> result(spec, context)
  end

  def encode(%{"today" => _}, _, _) do
    Elementary.Calendar.today()
  end

  def encode(%{"now" => _}, _, _) do
    Elementary.Calendar.now()
  end

  def encode(%{"date" => %{"in" => amount, "unit" => unit}} = spec, context, encoders) do
    with {:ok, amount} <- encode(amount, context, encoders) do
      Elementary.Calendar.time_in(amount, String.to_existing_atom(unit))
    end
    |> result(spec, context)
  end

  def encode(%{"date" => %{"ago" => amount, "unit" => unit}} = spec, context, encoders) do
    with {:ok, amount} <- encode(amount, context, encoders) do
      Elementary.Calendar.time_ago(amount, String.to_existing_atom(unit))
    end
    |> result(spec, context)
  end

  def encode(%{"date" => date_spec} = spec, context, encoders) do
    with {:ok, date_spec} <- encode(date_spec, context, encoders) do
      Elementary.Calendar.date(date_spec)
    end
    |> result(spec, context)
  end

  def encode(%{"formatDate" => date, "pattern" => pattern} = spec, context, encoders) do
    with {:ok, date} <- encode(date, context, encoders),
         {:ok, pattern} <- encode(pattern, context, encoders) do
      Elementary.Calendar.format_date(date, pattern)
    end
    |> result(spec, context)
  end

  def encode(%{"formatDate" => fields} = spec, context, encoders) do
    with {:ok, fields} <- encode(fields, context, encoders) do
      Elementary.Calendar.format_date(fields)
    end
    |> result(spec, context)
  end

  def encode(%{"monthFrom" => date} = spec, context, encoders) do
    with {:ok, date} <- encode(date, context, encoders) do
      Elementary.Calendar.month(date)
    end
    |> result(spec, context)
  end

  def encode(%{"yearFrom" => date} = spec, context, encoders) do
    with {:ok, date} <- encode(date, context, encoders) do
      Elementary.Calendar.year(date)
    end
    |> result(spec, context)
  end

  def encode(%{"dayFrom" => date} = spec, context, encoders) do
    with {:ok, date} <- encode(date, context, encoders) do
      Elementary.Calendar.day(date)
    end
    |> result(spec, context)
  end

  def encode(%{"durationSince" => date} = spec, context, encoders) do
    with {:ok, date} <- encode(date, context, encoders) do
      {:ok, Elementary.Calendar.duration_since(DateTime.utc_now(), date)}
    end
    |> result(spec, context)
  end

  def encode(%{"durationBetween" => dates} = spec, context, encoders) do
    with {:ok, [from, to]} <- encode_specs(dates, context, encoders) do
      {:ok, Elementary.Calendar.duration_since(to, from)}
    end
    |> result(spec, context)
  end

  def encode(%{"text" => value} = spec, context, encoders) do
    with {:ok, value} <- encode(value, context, encoders) do
      {:ok, "#{inspect(value)}"}
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
         {:ok, query} <- maybe_encode(http_spec["query"], nil, context, encoders),
         {:ok, body} <- maybe_encode(http_spec["body"], nil, context, encoders),
         {:ok, resp} =
           Elementary.Http.Client.run(
             debug: spec["debug"],
             method: method,
             url: url,
             body: body,
             headers: headers,
             query: query
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
      nil ->
        {:error,
         %{"error" => "no_such_encoder", "encoder" => encoder, "encoders" => Map.keys(encoders)}}

      spec ->
        encode(spec, context, encoders)
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

  def encode(%{"match" => value, "with" => expr} = spec, context, encoders) do
    with {:ok, value} <- encode(value, context, encoders),
         {:ok, expr} <- encode(expr, context, encoders) do
      case Decoder.decode(expr, value, context) do
        {:ok, _} ->
          {:ok, true}

        {:error, _} = err ->
          case Decoder.decode_error?(err) do
            true ->
              {:ok, false}

            false ->
              err
          end
      end
    end
    |> result(spec, context)
  end

  def encode(%{"expect" => expr, "in" => key} = spec, context, encoders) do
    with {:ok, encoded} <- encode(key, context, encoders) do
      case Decoder.decode(expr, encoded, context) do
        {:ok, decoded} ->
          case Map.get(spec, "where", nil) do
            nil ->
              {:ok, true}

            where ->
              encode(where, decoded, encoders)
          end

        other ->
          {:error, %{"error" => "expect", "actual" => other, "expected" => expr}}
      end
    end
    |> result(spec, context)
  end

  def encode(%{"file" => path} = spec, context, encoders) do
    with {:ok, encoded} <- encode(path, context, encoders) do
      path = "#{Elementary.Kit.assets()}/#{encoded}"

      with {:ok, %{type: type, size: size, atime: modified, ctime: created}} <- File.lstat(path),
           {:ok, data} <- File.read(path) do
        {:ok,
         %{
           "data" => data,
           "size" => size,
           "type" => type,
           "modified" => modified,
           "created" => created
         }}
      else
        {:error, :enoent} ->
          {:error, "not_found"}
      end
    end
    |> result(spec, context)
  end

  def encode(%{"env" => var, "default" => default} = spec, context, encoders) do
    with {:ok, var} <- encode(var, context, encoders),
         {:ok, default} <- encode(default, context, encoders) do
      {:ok, System.get_env(var, "#{default}")}
    end
    |> result(spec, context)
  end

  def encode(%{"env" => var} = spec, context, encoders) do
    with {:ok, var} <- encode(var, context, encoders) do
      {:ok, System.fetch_env!(var)}
    end
    |> result(spec, context)
  end

  def encode(%{"init" => init}, context, encoders) do
    encode_init(init, context, encoders)
  end

  def encode(%{"format" => template, "with" => params}, context, encoders) do
    with {:ok, template} <- encode(template, context, encoders),
         {:ok, params} <- encode(params, context, encoders) do
      {:ok, Mustache.render(template, Map.merge(context, params))}
    end
  end

  def encode(%{"format" => template, "params" => params}, context, encoders) do
    encode(%{"format" => template, "with" => params}, context, encoders)
  end

  def encode(%{"format" => template}, context, encoders) do
    with {:ok, template} <- encode(template, context, encoders) do
      {:ok, Mustache.render(template, context)}
    end
  end

  def encode(%{"downcase" => text}, context, encoders) do
    with {:ok, text} when is_binary(text) <- encode(text, context, encoders) do
      {:ok, String.downcase(text)}
    end
  end

  def encode(%{"capitalize" => text}, context, encoders) do
    with {:ok, text} when is_binary(text) <- encode(text, context, encoders) do
      {:ok, String.capitalize(text)}
    end
  end

  def encode(%{"trim" => text}, context, encoders) do
    with {:ok, text} when is_binary(text) <- encode(text, context, encoders) do
      {:ok, String.trim(text)}
    end
  end

  def encode(%{"entries" => entries} = spec, context, encoders) do
    with {:ok, entries} <- encode_specs(entries, context, encoders) do
      Enum.reduce(entries, %{}, fn %{"key" => key, "value" => value}, acc ->
        Map.put(acc, key, value)
      end)
    end
    |> result(spec, context)
  end

  def encode(%{"basicAuth" => creds} = spec, context, encoders) do
    with {:ok, %{"user" => user, "password" => pass}} <- encode(creds, context, encoders) do
      {:ok, "Basic " <> Base.encode64("#{user}:#{pass}")}
    end
    |> result(spec, context)
  end

  def encode(%{"html" => selector, "in" => data} = spec, context, encoders) do
    with {:ok, selector} <- encode(selector, context, encoders),
         {:ok, data} <- encode(data, context, encoders),
         {:ok, doc} <- Floki.parse_document(data),
         items <- Floki.find(doc, selector) do
      {:ok,
       Enum.map(items, fn {el, attrs, children} ->
         %{
           "element" => el,
           "attrs" => Enum.into(attrs, %{}),
           "children" =>
             Enum.map(children, fn c ->
               with true <- is_binary(c),
                    {:ok, c} <- Floki.parse_document(c) do
                 Floki.text(c)
                 |> String.replace("//", "")
               else
                 _ -> c
               end
             end)
         }
       end)}
    end
    |> result(spec, context)
  end

  def encode(%{"json" => data} = spec, context, encoders) do
    with {:ok, data} <- encode(data, context, encoders) do
      Jason.decode(data)
    end
    |> result(spec, context)
  end

  def encode(%{"fbEvent" => html} = spec, context, encoders) do
    with {:ok, html} <- encode(html, context, encoders) do
      Elementary.Facebook.parse_event(html)
    end
    |> result(spec, context)
  end

  def encode(%{"memory" => _}, _, _) do
    {:ok,
     %{
       "breakdown" => Elementary.Kit.memory(),
       "top" =>
         Elementary.Kit.procs()
         |> Enum.map(fn %{registered_name: name, memory: mem, message_queue_len: messages} ->
           %{"name" => name, "memory" => (mem / 1_000_000) |> Float.round(2), "queue" => messages}
         end)
     }}
  end

  def encode(spec, context, encoders) when is_map(spec) do
    encode(%{"object" => spec}, context, encoders)
  end

  def encode_init(%{} = map, _, _) when map_size(map) == 0 do
    {:ok, map, []}
  end

  def encode_init(%{"model" => model}, context, encoders) do
    with {:ok, encoded} <- encode(model, context, encoders) do
      {:ok, encoded, []}
    end
  end

  def encode_init(map, context, encoders) when is_map(map) do
    with {:ok, encoded} <- encode(map, context, encoders) do
      {:ok, encoded, []}
    end
  end

  defp maybe_encode(nil, default, _, _), do: {:ok, default}

  defp maybe_encode(spec, _, context, encoders) do
    encode(spec, context, encoders)
  end

  defp encode_specs(specs, context, encoders) when is_list(specs) do
    Enum.reduce_while(specs, [], fn spec, acc ->
      case encode(spec, context, encoders) do
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

  defp encode_items(spec, items, encoders) when is_list(items) do
    Enum.reduce_while(items, [], fn item, acc ->
      case encode(spec, item, encoders) do
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

  defp result({:error, _} = err, _, _) do
    err
  end

  defp result({:ok, _} = result, _, _), do: result
  defp result(result, _, _), do: {:ok, result}
end
