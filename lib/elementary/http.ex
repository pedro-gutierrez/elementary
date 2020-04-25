defmodule Elementary.Http do
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

  alias Elementary.App
  alias Elementary.Http.Headers
  require Logger

  @version "0.1"

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
      reply(req, "unknown", start, %{
        "status" => 404,
        "body" => %{}
      })
    else
      {:ok, mod} ->
        app = mod.name()
        {:ok, settings} = mod.settings()
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

        {req, resp} =
          with {:ok, model} <- App.init(mod, settings),
               {:ok, model2} <- App.filter(mod, @effect, data, model),
               {:ok, %{"status" => _} = resp} <-
                 App.decode(
                   mod,
                   @effect,
                   data,
                   Map.merge(model, model2)
                 ) do
            reply(req, app, start, resp)
          else
            {:stop, resp} ->
              reply(req, app, start, resp)

            {:error, %{error: %{"effect" => "http", "error" => :decode}}} ->
              reply(req, app, start, %{
                "status" => 400,
                "body" => %{}
              })

            {:error, req, e} ->
              resp = encoded_error(e)
              reply(req, app, start, resp)

            {:error, e} ->
              resp = encoded_error(e)
              reply(req, app, start, resp)

            {:ok, other} ->
              resp = encoded_error(%{error: :invalid_http_response, data: other})
              reply(req, app, start, resp)

            other ->
              resp = encoded_error(%{unexpected: other})
              reply(req, app, start, resp)
          end

        if mod.debug() do
          Logger.info(
            "#{
              inspect(%{
                app: app,
                req: data,
                resp: resp
              })
            }"
          )
        end

        {:ok, req, state}
    end
  end

  defp encoded_error(err) do
    Logger.error("#{inspect(err, pretty: true)}")
    %{"status" => 500, "headers" => %{}, "body" => %{}}
  end

  defp resolve_app(_, mod) when is_atom(mod), do: {:ok, mod}

  defp resolve_app(%{method: method}, apps) do
    case apps[method] do
      nil ->
        {:error, :not_found}

      mod ->
        {:ok, mod}
    end
  end

  defp resolve_app(_, _), do: {:error, :not_found}

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

    resp = %{status: status, headers: headers, body: body}

    req =
      :cowboy_req.reply(
        status,
        headers,
        body,
        req
      )

    {req, resp}
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
    def method("post"), do: :post
    def method("delete"), do: :delete
    def method("put"), do: :put

    defp response({:ok, %HTTPoison.Response{body: body, headers: headers, status_code: code}}) do
      headers =
        headers
        |> Enum.into(%{})
        |> Headers.normalized()

      body = decode_body(body, headers)
      %{"status" => code, "headers" => headers, "body" => body}
    end

    defp response({:error, %HTTPoison.Error{reason: error}}) do
      %{"error" => error}
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
