defmodule Elementary.Http do
  @moduledoc false
  defmodule Helper do
    defmacro __using__(_) do
      quote do
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

        defp encoded_error(e) do
          %{"status" => 500, "headers" => %{}, "body" => %{}}
        end

        defp json(req, app, started, %{"status" => status, "body" => body}) do
          elapsed = System.system_time(:microsecond) - started

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

        defp json(req, app, started, %{
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
      end
    end
  end

  defmodule Handler do
    use Elementary.Http.Helper
    alias Elementary.App.Helper, as: App

    def init(
          %{
            bindings: params,
            method: method,
            headers: headers
          } = req,
          [app, mod, settings] = state
        ) do
      start = System.system_time(:microsecond)

      req =
        with {:ok, req, body} <- body(req),
             {:ok, model} <- App.init(mod, settings),
             {:ok, resp} <-
               App.decode(
                 mod,
                 :http,
                 %{
                   "method" => method,
                   "headers" => headers,
                   "params" => encoded_params(params),
                   "body" => body
                 },
                 model
               ) do
          json(req, app, start, resp)
        else
          {:error, req, e} ->
            resp = encoded_error(e)
            json(req, app, start, resp)

          {:error, %{effect: :http, error: :no_decoder}} ->
            json(req, app, start, %{
              "status" => 400,
              "headers" => %{},
              "body" => %{}
            })

          {:error, e} ->
            resp = encoded_error(e)
            json(req, app, start, resp)
        end

      {:ok, req, state}
    end
  end
end
