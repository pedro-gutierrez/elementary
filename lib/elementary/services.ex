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

    alias Elementary.{Index, App, Streams}

    def run(app, effect, data) do
      case Index.spec("app", app) do
        {:ok, spec} ->
          spec = {__MODULE__, %{app: app, spec: spec, effect: effect}}
          {:ok, pid} = DynamicSupervisor.start_child(Elementary.Services, spec)
          GenServer.call(pid, {:data, data})

        :not_found ->
          Logger.warn("Undefined app \"#{app}\"")
          {:error, :no_such_app}
      end
    end

    def start_link(state) do
      GenServer.start_link(__MODULE__, state)
    end

    def init(state) do
      {:ok, state}
    end

    def handle_call({:data, data}, _, %{app: app, spec: spec, effect: effect}) do
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

    defp with_telemetry({micros, res0} = res, app, %{"spec" => spec}) do
      spec
      |> telemetry_profile()
      |> maybe_report_telemetry(micros, res0, app)

      res
    end

    defp telemetry_profile(%{"telemetry" => profile}), do: profile

    defp telemetry_profile(_), do: "fast"

    defp maybe_report_telemetry("fast", micros, res, app) when micros > 150_000 do
      report_telemetry(micros, res, app, "danger")
    end

    defp maybe_report_telemetry("fast", micros, res, app) when micros > 100_000 do
      report_telemetry(micros, res, app, "warning")
    end

    defp maybe_report_telemetry("fast", _, _, _), do: :ok

    defp maybe_report_telemetry("average", micros, res, app) when micros > 500_0000 do
      report_telemetry(micros, res, app, "danger")
    end

    defp maybe_report_telemetry("average", micros, res, app) when micros > 300_0000 do
      report_telemetry(micros, res, app, "warning")
    end

    defp maybe_report_telemetry("average", _, _, _), do: :ok

    defp maybe_report_telemetry("slow", micros, res, app) when micros > 1_500_0000 do
      report_telemetry(micros, res, app, "danger")
    end

    defp maybe_report_telemetry("slow", micros, res, app) when micros > 1_000_0000 do
      report_telemetry(micros, res, app, "warning")
    end

    defp maybe_report_telemetry(_, _, _, _), do: :ok

    defp report_telemetry(micros, res0, app, severity) do
      status =
        case res0 do
          {:error, _} ->
            "error"

          _ ->
            "ok"
        end

      Streams.write_async("telemetry", %{
        "app" => app,
        "status" => status,
        "duration" => trunc(micros / 1000),
        "severity" => severity
      })
    end

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

      Streams.write_async("errors", error)

      Logger.error("#{inspect(error, pretty: true)}")

      res
    end

    defp with_error(res, _, _, _, _) do
      res
    end
  end
end
