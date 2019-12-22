defmodule Elementary.Http do
  @moduledoc false

  defmodule Rest do
    defmacro __using__(_) do
      quote do
        alias Elementary.Kit

        @limit "@limit"
        @offset "@offset"
        @pagination [@limit, @offset]

        def init(
              %{bindings: %{id: id, version: version} = bindings, method: method} = req,
              [app, settings] = state
            ) do
          start = System.system_time(:microsecond)

          settings = with_store(app, settings)

          {req, res} =
            case Kit.parse_int(version) do
              {:ok, version} ->
                case method do
                  "PUT" ->
                    case body(req) do
                      {:ok, req, body} ->
                        {req, create(id, version, body, app, settings)}

                      {:error, req, _} ->
                        {req, {:error, :invalid}}
                    end

                  "DELETE" ->
                    {req, delete(id, version, app, settings)}

                  _ ->
                    {req, {:error, :not_implemented}}
                end

              {:error, :invalid} ->
                {req, {:error, :invalid}}
            end

          elapsed = System.system_time(:microsecond) - start

          req = json(req, app, elapsed, res)
          {:ok, req, state}
        end

        def init(
              %{bindings: %{id: id}, method: method} = req,
              [app, settings] = state
            ) do
          start = System.system_time(:microsecond)

          settings = with_store(app, settings)

          {req, res} =
            case method do
              "GET" ->
                {req, fetch(id, app, settings)}

              "PUT" ->
                case body(req) do
                  {:ok, req, body} ->
                    {req, create(id, 1, body, app, settings)}

                  {:error, req, _} ->
                    {req, {:error, :invalid}}
                end

              _ ->
                {req, {:error, :not_implemented}}
            end

          elapsed = System.system_time(:microsecond) - start

          req = json(req, app, elapsed, res)
          {:ok, req, state}
        end

        def init(
              %{method: method} = req,
              [app, settings] = state
            ) do
          start = System.system_time(:microsecond)

          settings = with_store(app, settings)

          {req, res} =
            case method do
              "GET" ->
                query = Enum.into(:cowboy_req.parse_qs(req), %{})
                {opts, filter} = Map.split(query, @pagination)
                {req, list(filter, pagination(opts), app, settings)}

              _ ->
                {req, {:error, :not_implemented}}
            end

          elapsed = System.system_time(:microsecond) - start

          req = json(req, app, elapsed, res)
          {:ok, req, state}
        end

        defp with_store(app, settings) do
          {:ok, store} = Elementary.Index.Store.get(app)
          Map.put(settings, "store", store)
        end

        defp pagination(opts) do
          [
            limit: Map.get(opts, @limit) |> Kit.parse_int(20),
            offset: Map.get(opts, @offset) |> Kit.parse_int(0)
          ]
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

        defp reply(:ok), do: {200, %{}}

        defp reply({:ok, %{"status" => status, "body" => body}}), do: {status, body}
        defp reply({:ok, %{"status" => status}}), do: {status, %{}}

        defp reply({:ok, data}), do: {200, data}
        defp reply({:error, reason}), do: {status(reason), %{}}

        defp status(:not_found), do: 404
        defp status(:invalid), do: 400
        defp status(:unauthorized), do: 401
        defp status(:forbidden), do: 403
        defp status(:conflict), do: 409
        defp status(:not_implemented), do: 501
        defp status(_), do: 500

        defp json(req, app, elapsed, res) do
          {status, data} = reply(res)
          json(req, app, elapsed, status, data)
        end

        defp json(req, app, elapsed, status, data) do
          :cowboy_req.reply(
            status,
            %{
              "content-type" => "application/json",
              "app" => "#{app}",
              "elapsed" => "#{elapsed}"
            },
            Jason.encode!(data),
            req
          )
        end
      end
    end
  end

  defmacro __using__(app: app) do
    quote do
      require Logger
      @effect :http
      @app unquote(app)

      def app(), do: @app
      def protocol(), do: :http
      def permanent(), do: false

      defstruct start: nil,
                pid: nil,
                mod: nil,
                ref: nil

      def init(%{:headers => headers, :method => method} = req, [app_module]) do
        t0 = System.system_time(:microsecond)
        {req, body} = request_body!(req)
        params = request_params!(req)

        data = %{
          "method" => method,
          "params" => params,
          "headers" => headers,
          "body" => body
        }

        {:ok, pid} = Elementary.Apps.launch(app_module)
        ref = Process.monitor(pid)
        app_module.update(pid, @effect, data)

        {:cowboy_loop, req,
         %__MODULE__{
           start: t0,
           pid: pid,
           mod: app_module,
           ref: ref
         }}
      end

      def info(%{"status" => status, "headers" => headers, "body" => body}, req, state) do
        respond(status, headers, body, req, state)
      end

      def info({:DOWN, ref, :process, pid, reason}, req, %{ref: ref, pid: pid} = state) do
        Logger.error(
          "Process terminated: #{
            inspect(
              pid: pid,
              reason: reason
            )
          }"
        )

        info(:crashed, req, state)
      end

      def info(e, req, state) do
        e
        |> error_code()
        |> json(e, req, state)
      end

      defp error_code(:no_decoder), do: 400
      defp error_code(_), do: 500

      defp json(code, body, req, state) do
        respond(
          code,
          %{"content-type" => "application/json"},
          body,
          req,
          state
        )
      end

      defp respond(status, headers, body, req, state) do
        body = encoded_body!(body, headers)
        elapsed = System.system_time(:microsecond) - state.start

        req =
          :cowboy_req.reply(
            status,
            encoded_headers(headers, %{
              "elementary-app" => @app,
              "elementary-micros" => elapsed
            }),
            body,
            req
          )

        Process.demonitor(state.ref)
        state.mod.terminate(state.pid)
        {:stop, req, state}
      end

      defp encoded_headers(h1, h2) do
        h1
        |> Map.merge(h2)
        |> Enum.reduce([], fn {k, v}, m ->
          [{k, "#{v}"} | m]
        end)
        |> Enum.into(%{})
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

      defp request_params!(req) do
        :cowboy_req.bindings(req)
        |> Map.new(fn {k, v} ->
          {"#{k}", v}
        end)
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
