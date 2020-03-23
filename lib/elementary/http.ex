defmodule Elementary.Http do
  @effect "http"

  alias Elementary.App
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
        headers = normalized_content_type(headers)

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
               {:ok, %{"status" => _, "body" => _} = resp} <-
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

            {:error, req, e} ->
              resp = encoded_error(mod, e)
              reply(req, app, start, resp)

            {:error, %{"effect" => @effect, "error" => :decode}} ->
              reply(req, app, start, %{
                "status" => 400,
                "body" => %{}
              })

            {:error, e} ->
              resp = encoded_error(mod, e)
              reply(req, app, start, resp)

            {:ok, other} ->
              resp = encoded_error(mod, error: "invalid_http_response", data: other)
              reply(req, app, start, resp)

            other ->
              resp = encoded_error(mod, unexpected: other)
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

        case json?(headers) do
          true ->
            case Jason.decode(data) do
              {:ok, data} ->
                {:ok, req, data}

              {:error, e} ->
                Logger.warn("Invalid JSON request: #{inspect(e)}")
                {:ok, req, data}
            end

          false ->
            {:ok, req, data}
        end
    end
  end

  @json_mime "application/json"

  defp normalized_content_type(
         %{"content-type" => "application/json;charset=" <> charset} = headers
       ) do
    Map.merge(headers, %{
      "content-type" => @json_mime,
      "charset" => charset
    })
  end

  defp normalized_content_type(headers) do
    headers
  end

  defp json?(headers) do
    @json_mime == (headers["content-type"] || "")
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

  defp encoded_error(app, e) do
    Logger.error("#{inspect(Keyword.merge(e, app: app), pretty: true)}")
    %{"status" => 500, "headers" => %{}, "body" => %{}}
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
      case headers["content-type"] do
        @json_mime ->
          Jason.encode!(body)

        _ ->
          case is_binary(body) do
            true ->
              body

            false ->
              ""
          end
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
      headers = Enum.into(headers, %{})
      body = maybe_json_decode(body, headers)
      %{"status" => code, "headers" => headers, "body" => body}
    end

    defp response({:error, %HTTPoison.Error{reason: error}}) do
      %{"error" => error}
    end

    defp with_request_body(req, nil, _), do: req

    defp with_request_body(req, body, headers) do
      %HTTPoison.Request{req | body: maybe_json_encode(body, headers)}
    end

    defp with_response_time(resp, micros) do
      Map.put(resp, "time", micros)
    end

    defp with_request(resp, req) do
      Map.put(resp, "request", %{
        "method" => "#{req.method}",
        "url" => req.url,
        "headers" => Enum.into(req.headers, %{}),
        "body" => req.body
      })
    end

    defp with_debug(resp, opts) do
      if opts[:debug] do
        IO.inspect(resp)
      end

      resp
    end

    defp maybe_json_encode(body, req) do
      case json?(req) do
        true ->
          Jason.encode!(body)

        false ->
          body
      end
    end

    defp maybe_json_decode(body, resp) do
      case json?(resp) do
        true ->
          Jason.decode!(body)

        false ->
          body
      end
    end

    @json "application/json"

    defp json?(opts) when is_map(opts) do
      opts["content-type"] == @json
    end

    defp json?(_), do: false
  end
end
