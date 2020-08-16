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

    alias Elementary.{Index, App, Streams.Stream}

    def run(app, effect, data) do
      spec = {__MODULE__, %{app: app, effect: effect}}

      with {:ok, pid} <- DynamicSupervisor.start_child(Elementary.Services, spec) do
        GenServer.call(pid, {:data, data})
      end
    end

    def start_link(app) do
      GenServer.start_link(__MODULE__, app)
    end

    def init(app) do
      {:ok, app}
    end

    def handle_call({:data, data}, _, %{app: app, effect: effect}) do
      {_, res} =
        :timer.tc(fn ->
          spec = Index.spec!("app", app)
          App.run(spec, effect, data)
        end)
        |> with_telemetry(app)
        |> with_error_logging(app, effect, data)

      {:stop, :normal, res, nil}
    end

    defp with_telemetry({micros, res0} = res, app) when micros > 10000 do
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
        "duration" => micros / 1000
      })

      res
    end

    defp with_telemetry(res, _), do: res

    defp with_error_logging({_, {:error, e}} = res, app, effect, data) do
      data =
        cond do
          is_map(data) or is_binary(data) or is_number(data) ->
            data

          true ->
            "#{inspect(data)}"
        end

      Stream.write_async("errors", %{
        "app" => app,
        "effect" => effect,
        "data" => data,
        "error" => e
      })

      res
    end

    defp with_error_logging(res, _, _, _) do
      res
    end
  end
end
