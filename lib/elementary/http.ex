defmodule Elementary.Http do
  @effect "http"

  alias Elementary.App

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

    req =
      with {:ok, req, body} <- body(req),
           {:ok, model} <- App.init(mod, settings),
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
      end

    {:ok, req, state}
  end

  defp body(req) do
    case :cowboy_req.has_body(req) do
      false ->
        {:ok, req, %{}}

      true ->
        {:ok, data, req} = :cowboy_req.read_body(req)

        case Jason.decode(data) do
          {:ok, data} ->
            {:ok, req, data}

          {:error, e} ->
            {:error, req, e}
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

  defp encoded_error(_) do
    %{"status" => 500, "headers" => %{}, "body" => %{}}
  end

  defp reply(req, app, started, %{
         "status" => status,
         "headers" => %{"content-type" => "application/json"} = headers,
         "body" => body
       }) do
    body = Jason.encode!(body)
    headers = encoded_headers(headers)
    elapsed = System.system_time(:microsecond) - started

    :cowboy_req.reply(
      status,
      Map.merge(
        %{
          "content-type" => "application/json",
          "app" => "#{app}",
          "time" => "#{elapsed}"
        },
        headers
      ),
      body,
      req
    )
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

    :cowboy_req.reply(
      status,
      %{
        "app" => "#{app}",
        "time" => "#{elapsed}"
      },
      body,
      req
    )
  end
end
