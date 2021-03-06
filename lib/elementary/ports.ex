defmodule Elementary.Ports do
  @moduledoc false

  use Supervisor
  alias Elementary.{Index}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    Index.specs("port")
    |> Enum.map(&port_spec(&1))
    |> Supervisor.init(strategy: :one_for_one)
  end

  def port_name(%{"name" => name}), do: port_name(name)
  def port_name(name), do: String.to_atom("#{name}_port")

  defp port_spec(spec) do
    name = port_name(spec)

    %{
      id: name,
      start:
        {Elementary.Ports.Port, :start_link,
         [
           spec
         ]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  defmodule Port do
    alias Elementary.Ports.MetricsExporter

    def start_link(%{"name" => name, "spec" => %{"port" => port}}) do
      routes =
        "app"
        |> Index.specs()
        |> Enum.flat_map(fn
          %{"name" => app, "spec" => %{"routes" => %{^name => routes}}} ->
            Enum.map(routes, fn {method, path} ->
              [app: app, path: path, method: method, scheme: :http]
            end)

          _ ->
            []
        end)
        |> Enum.reduce(%{}, fn [app: app, path: path, method: method, scheme: :http], acc ->
          methods = acc[path] || %{}
          Map.put(acc, path, Map.put(methods, method, app))
        end)
        |> Enum.map(fn {path, methods} ->
          %{"path" => path, "apps" => methods}
        end)

      dispatch_rules =
        Enum.map(routes, fn
          %{"path" => route, "apps" => apps} ->
            {route, Elementary.Http,
             [
               Enum.reduce(apps, %{}, fn {method, app}, acc ->
                 Map.put(
                   acc,
                   String.upcase(method),
                   app
                 )
               end)
             ]}
        end)

      dispatch =
        :cowboy_router.compile([
          {:_,
           dispatch_rules ++
             [{"/metrics", MetricsExporter, []}] ++
             [
               {"/[...]", :cowboy_static,
                {:dir, Elementary.Kit.assets(),
                 [
                   {:mimetypes, :cow_mimetypes, :all}
                 ]}}
             ]}
        ])

      {:ok, pid} =
        :cowboy.start_clear(
          name,
          %{num_acceptors: :erlang.system_info(:schedulers), socket_opts: [port: port]},
          %{:env => %{:dispatch => dispatch}}
        )

      IO.inspect(
        port: name,
        port: port,
        routes:
          routes
          |> Enum.reduce(%{}, fn %{"path" => path, "apps" => methods}, acc ->
            Map.put(acc, path, Map.keys(methods) |> Enum.map(&String.to_atom(&1)))
          end)
      )

      # clear default prometheus collectors
      :prometheus_registry.clear()

      {:ok, pid}
    end
  end

  defmodule MetricsExporter do
    @moduledoc """
    Http exporter that exposes Prometheus metrics
    """

    def init(req, state) do
      body = Prometheus.Format.Text.format()

      req =
        :cowboy_req.reply(
          200,
          %{"content-type" => "text/plain"},
          body,
          req
        )

      {:ok, req, state}
    end
  end
end
