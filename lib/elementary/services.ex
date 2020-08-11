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

    alias Elementary.{Index, App}

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
      spec = Index.spec!("app", app)
      res = App.run(spec, effect, data)
      # TODO telemetry and logging
      {:stop, :normal, res, nil}
    end
  end
end
