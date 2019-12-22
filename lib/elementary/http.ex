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
                  "POST" ->
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

              "POST" ->
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

              "POST" ->
                case body(req) do
                  {:ok, req, body} ->
                    {req, create(UUID.uuid4(), 1, body, app, settings)}

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
end
