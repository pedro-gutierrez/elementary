defmodule Elementary.Http do
  @effect "http"

  alias Elementary.App
  require Logger

  def init(
        %{
          bindings: params,
          method: method,
          headers: headers
        } = req,
        [mod] = state
      ) do
    start = System.system_time(:microsecond)
    app = mod.name()
    {:ok, settings} = mod.settings()

    {:ok, req, body} = body(req, headers)

    {req, resp} =
      with {:ok, model} <- App.init(mod, settings),
           {:ok, %{"status" => _, "body" => _} = resp} <-
             App.decode(
               mod,
               @effect,
               %{
                 "method" => method,
                 "headers" => headers,
                 "params" => encoded_params(params),
                 "body" => body
               },
               model
             ) do
        reply(req, app, start, resp)
      else
        {:error, req, e} ->
          resp = encoded_error(e)
          reply(req, app, start, resp)

        {:error, %{"effect" => @effect, "error" => :decode}} ->
          reply(req, app, start, %{
            "status" => 400,
            "body" => %{}
          })

        {:error, e} ->
          resp = encoded_error(e)
          reply(req, app, start, resp)

        {:ok, _} ->
          resp = encoded_error("invalid_response")
          reply(req, app, start, resp)

        other ->
          resp = encoded_error(%{"unexpected" => other})
          reply(req, app, start, resp)
      end

    if mod.debug() do
      Logger.info(
        "#{
          inspect(%{
            app: app,
            req: %{
              headers: headers,
              body: body,
              params: params
            },
            resp: resp
          })
        }"
      )
    end

    {:ok, req, state}
  end

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

  defp encoded_error(e) do
    Logger.error("#{inspect(e)}")
    %{"status" => 500, "headers" => %{}, "body" => %{}}
  end

  defp reply(req, app, started, %{
         "status" => status,
         "headers" => %{"content-type" => @json_mime} = headers,
         "body" => body
       }) do
    body = Jason.encode!(body)
    headers = encoded_headers(headers)
    elapsed = System.system_time(:microsecond) - started

    headers =
      Map.merge(
        %{
          "content-type" => "application/json",
          "app" => "#{app}",
          "time" => "#{elapsed}"
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

  defp reply(req, app, started, %{"status" => status, "body" => body}) do
    elapsed = System.system_time(:microsecond) - started

    body =
      case is_binary(body) do
        true ->
          body

        false ->
          ""
      end

    headers = %{
      "app" => "#{app}",
      "time" => "#{elapsed}"
    }

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
          headers: opts[:headers] || []
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
