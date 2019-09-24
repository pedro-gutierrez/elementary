defmodule Elementary.Http do
  @moduledoc false

  defmacro __using__(app: app) do
    quote do
      def app(), do: unquote(app)
      def protocol(), do: :http
      def permanent(), do: false

      def init(%{:headers => headers, :method => method} = req, [app_module]) do
        t0 = System.system_time(:microsecond)
        {req, body} = request_body!(req)
        data = %{"method" => method, "headers" => headers, "body" => body}
        {:ok, pid} = Elementary.Apps.launch(app_module)
        app_module.update(pid, data)
        {:cowboy_loop, req, [start: t0, pid: pid, mod: app_module]}
      end

      def info([status: status, headers: headers, body: body], req, state) do
        respond(status, headers, body, req, state)
      end

      def info(error, req, state) do
        state[:mod].terminate(state[:pid])
        error("#{error}", req, state)
      end

      defp error(reason, req, state) do
        respond(
          500,
          %{"content-type" => "application/json"},
          %{"reason" => reason},
          req,
          state
        )
      end

      defp respond(status, headers, body, req, state) do
        body = encoded_body!(body, headers)
        elapsed = System.system_time(:microsecond) - state[:start]

        req =
          :cowboy_req.reply(
            status,
            Map.merge(headers, %{
              "elementary-app" => "#{app()}",
              "elementary-micros" => "#{elapsed}"
            }),
            body,
            req
          )

        {:stop, req, state}
      end

      defp encoded_body!(body, %{"content-type" => "application/json"}) do
        Jason.encode!(body)
      end

      defp encoded_body!(body, _) do
        body
      end

      defp request_body!(%{:headers => headers} = req) do
        case :cowboy_req.has_body(req) do
          false ->
            {req, ""}

          true ->
            {:ok, data, req} = :cowboy_req.read_body(req)
            {req, decoded_body!(data, headers)}
        end
      end

      defp decoded_body!(body, %{"content-type" => "application/json"}) do
        Jason.decode!(body)
      end

      defp decoded_body!(body, _) do
        body
      end
    end
  end
end
