defmodule Elementary.Http do
  alias Elementary.{Streams.Stream}

  @effect "http"

  defmodule Headers do
    import ContentType

    def normalized(headers) do
      headers
      |> downcased()
      |> with_simple_content_type()
    end

    defp downcased(headers) do
      Enum.map(headers, fn {k, v} ->
        {String.downcase(k), v}
      end)
      |> Enum.into(%{})
    end

    def with_simple_content_type(%{"content-type" => ct} = headers) do
      case content_type(ct) do
        {:ok, app, kind, extra} ->
          Map.merge(
            headers,
            Map.merge(
              extra,
              %{"content-type" => "#{app}/#{kind}"}
            )
          )

        _ ->
          headers
      end
    end

    def with_simple_content_type(headers) do
      headers
    end

    def mime(headers) when is_map(headers) do
      mime(headers["content-type"])
    end

    def mime("application/json"), do: :json
    def mime("text/javascript"), do: :json
    def mime("application/x-www-form-urlencoded"), do: :form_urlencoded
    def mime(_), do: :other
  end

  alias Elementary.{Services.Service, Index}
  alias Elementary.Http.Headers
  require Logger

  @version "0.1"

  # This is left here as a reference for
  # performance testing, in order to measure the impact
  # of our framework in response times
  ## defp init(req, state) do
  ##  req =
  ##    :cowboy_req.reply(
  ##      200,
  ##      %{},
  ##      "hello",
  ##      req
  ##    )

  ##  {:ok, req, state}
  ## end

  def init(
        %{
          bindings: params,
          method: method,
          headers: headers
        } = req,
        [spec] = state
      ) do
    start = System.system_time(:microsecond)

    with {:error, :not_found} <- resolve_app(req, spec) do
      reply(req, "unknown", method, start, %{
        "status" => 404,
        "body" => %{}
      })
    else
      {:ok, app} ->
        headers = Headers.normalized(headers)

        {:ok, req, body} = body(req, headers)
        query = :cowboy_req.parse_qs(req) |> Enum.into(%{})

        data = %{
          "method" => method,
          "headers" => headers,
          "params" => encoded_params(params),
          "body" => body,
          "query" => query
        }

        {req, _} =
          with {:ok, %{"status" => _} = resp} <- Service.run(app, @effect, data) do
            reply(req, app, method, start, resp)
          else
            {:stop, resp} ->
              reply(req, app, method, start, resp)

            {:error, %{error: %{"effect" => "http", "error" => :decode}}} ->
              reply(req, app, method, start, %{
                "status" => 400,
                "body" => %{}
              })

            {:error, req, e} ->
              resp = error_response(app, e)
              reply(req, app, method, start, resp)

            {:error, e} ->
              resp = error_response(app, e)
              reply(req, app, method, start, resp)

            {:ok, other} ->
              resp = error_response(app, %{"invalid_http_response" => other})
              reply(req, app, method, start, resp)

            other ->
              resp = error_response(app, %{"unexpected" => other})
              reply(req, app, method, start, resp)
          end

        {:ok, req, state}
    end
  end

  defp error_response(_, err) do
    %{"status" => 500, "headers" => %{}, "body" => %{}, "error" => err}
  end

  defp resolve_app(%{method: method}, apps) do
    case apps[method] do
      nil ->
        {:error, :not_found}

      app ->
        {:ok, app}
    end
  end

  defp body(req, headers) do
    case :cowboy_req.has_body(req) do
      false ->
        {:ok, req, %{}}

      true ->
        {:ok, data, req} = :cowboy_req.read_body(req)

        case Headers.mime(headers) do
          :json ->
            case Jason.decode(data) do
              {:ok, data} ->
                {:ok, req, data}

              {:error, e} ->
                Logger.warn("Invalid JSON request: #{inspect(e)}")
                {:ok, req, data}
            end

          :form_urlencoded ->
            {:ok, req, URI.decode_query(data)}

          _ ->
            {:ok, req, data}
        end
    end
  end

  defp encoded_headers(h) do
    Enum.reduce(h, %{}, fn {k, v}, acc ->
      Map.put(acc, "#{k}", "#{v}")
    end)
  end

  defp encoded_params(h) do
    Enum.reduce(h, %{}, fn {k, v}, acc ->
      Map.put(acc, "#{k}", v)
    end)
  end

  defp reply(
         req,
         app,
         method,
         started,
         %{
           "status" => status
         } = resp
       ) do
    headers = resp["headers"] || %{}

    body = resp["body"] || ""

    body =
      case Headers.mime(headers) do
        :json ->
          Jason.encode!(body)

        :form_urlencoded ->
          URI.encode_query(body)

        _ when is_binary(body) ->
          body

        _ ->
          ""
      end

    headers = encoded_headers(headers)
    elapsed = Elementary.Kit.duration(started)

    headers =
      Map.merge(
        %{
          "app" => "#{app}",
          "time" => "#{elapsed}",
          "elementary-version" => @version,
          "access-control-max-age" => "1728000",
          "access-control-allow-methods" => "*",
          "access-control-allow-headers" => "*",
          "access-control-allow-origin" => "*"
        },
        headers
      )

    resp2 = %{status: status, headers: headers, body: body}

    req =
      :cowboy_req.reply(
        status,
        headers,
        body,
        req
      )

    maybe_access_log(app, method, status, elapsed)

    if status >= 500 do
      Logger.error("#{inspect(resp, pretty: true)}")
    end

    {req, resp2}
  end

  defp maybe_access_log(app, method, status, elapsed) do
    case Index.spec("app", app) do
      :not_found ->
        :ok

      {:ok, %{"spec" => %{"access" => false}}} ->
        :ok

      {:ok, _} ->
        access_log_record = %{
          "app" => app,
          "method" => method,
          "status" => status,
          "elapsed" => floor(elapsed / 1000)
        }

        Stream.write_async("access", access_log_record)
        :ok
    end
  end

  defmodule Client do
    def run(opts) do
      req =
        %HTTPoison.Request{
          method: method(opts[:method] || "get"),
          url: opts[:url],
          headers: opts[:headers] || [],
          params: opts[:query] || %{}
        }
        |> with_request_body(opts[:body], opts[:headers])

      {micros, res} =
        :timer.tc(fn ->
          HTTPoison.request(req)
        end)

      {:ok,
       res |> response |> with_response_time(micros) |> with_request(req) |> with_debug(opts)}
    end

    def method("get"), do: :get
    def method("GET"), do: :get
    def method("post"), do: :post
    def method("POST"), do: :post
    def method("delete"), do: :delete
    def method("DELETE"), do: :delete
    def method("put"), do: :put
    def method("PUT"), do: :put

    defp response({:ok, %HTTPoison.Response{body: body, headers: headers, status_code: code}}) do
      headers =
        headers
        |> Enum.into(%{})
        |> Headers.normalized()

      body = decode_body(body, headers)
      %{"status" => code, "headers" => headers, "body" => body}
    end

    defp response({:error, %HTTPoison.Error{reason: error}}) do
      %{"error" => "#{error}"}
    end

    defp decode_body(body, headers) do
      case Headers.mime(headers) do
        :json ->
          Jason.decode!(body)

        :form_urlencoded ->
          URI.decode_query(body)

        :other ->
          body
      end
    end

    defp with_request_body(req, nil, _), do: req

    defp with_request_body(req, body, headers) do
      with {:ok, encoded} <- encode_body(body, headers) do
        %HTTPoison.Request{req | body: encoded}
      end
    end

    defp with_response_time(resp, micros) do
      Map.put(resp, "time", micros)
    end

    defp with_request(resp, req) do
      Map.put(resp, "request", %{
        "method" => "#{req.method}",
        "url" => req.url,
        "headers" => Enum.into(req.headers, %{}),
        "body" => req.body,
        "query" => req.params
      })
    end

    defp with_debug(resp, opts) do
      if opts[:debug] do
        IO.inspect(resp)
      end

      resp
    end

    defp encode_body(body, headers) do
      case headers["content-type"] do
        "application/json" ->
          {:ok, Jason.encode!(body)}

        "application/x-www-form-urlencoded" ->
          {:ok, url_form_encoded_body(body)}

        _ ->
          {:ok, body}
      end
    end

    defp url_form_encoded_body(body) when is_map(body) do
      body
      |> Enum.map(fn {k, v} ->
        "#{k}=#{URI.encode_www_form(v)}"
      end)
      |> Enum.join("&")
    end

    defp url_form_encoded_body(text) when is_binary(text) do
      URI.encode_www_form(text)
    end
  end
end
