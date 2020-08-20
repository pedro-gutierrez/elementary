defmodule Elementary.Services do
  use DynamicSupervisor

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defmodule Service do
    use GenServer, restart: :temporary
    require Logger

    alias Elementary.{Index, App, Streams.Stream}

    def run(app, effect, data) do
      spec = {__MODULE__, %{app: app, effect: effect}}

      {:ok, pid} = DynamicSupervisor.start_child(Elementary.Services, spec)
      GenServer.call(pid, {:data, data})
    end

    def start_link(app) do
      GenServer.start_link(__MODULE__, app)
    end

    def init(app) do
      {:ok, app}
    end

    def handle_call({:data, data}, _, %{app: app, effect: effect}) do
      spec = Index.spec!("app", app)

      {_, res} =
        :timer.tc(fn ->
          App.run(spec, effect, data)
        end)
        |> with_debug(app, spec)
        |> with_telemetry(app, spec)
        |> with_error(app, effect, data, spec)

      {:stop, :normal, res, nil}
    end

    defp with_debug({micros, res2} = res, app, %{"spec" => %{"debug" => true}}) do
      IO.inspect(%{
        app: app,
        elapsed: micros,
        result: res2
      })

      res
    end

    defp with_debug(res, _, _) do
      res
    end

    defp with_telemetry(res, _, %{"spec" => %{"telemetry" => false}}) do
      res
    end

    defp with_telemetry({micros, res0} = res, app, _) when micros > 10000 do
      status =
        case res0 do
          {:error, _} ->
            "error"

          _ ->
            "ok"
        end

      Stream.write_async("telemetry", %{
        "app" => app,
        "status" => status,
        "duration" => trunc(micros / 1000)
      })

      res
    end

    defp with_telemetry(res, _, _), do: res

    defp with_error(res, _, _, _, %{"spec" => %{"errors" => false}}) do
      res
    end

    defp with_error({_, {:error, e}} = res, app, effect, data, _) do
      data =
        cond do
          is_map(data) or is_binary(data) or is_number(data) ->
            data

          true ->
            "#{inspect(data)}"
        end

      error = %{
        "app" => app,
        "effect" => effect,
        "data" => data,
        "error" => e
      }

      Stream.write_async("errors", error)

      Logger.error("#{inspect(error, pretty: true)}")

      res
    end

    defp with_error(res, _, _, _, _) do
      res
    end
  end
end
