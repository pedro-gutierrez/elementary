defmodule Elementary.Metrics do
  @moduledoc """
  Everything about exporting Prometheus Metrics
  """

  use Supervisor
  alias Elementary.Index
  alias Elementary.Metrics.Port
  alias Elementary.Metrics.Exporter

  @instruments [
    Elementary.Channel.Instrumenter
  ]

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    setup_instruments()

    Index.specs("metrics")
    |> Enum.map(fn spec ->
      {Port, spec}
    end)
    |> Supervisor.init(strategy: :one_for_one)
  end

  def setup_instruments do
    :prometheus_registry.clear()

    @instruments
    |> Enum.each(fn mod -> mod.setup() end)
  end

  defmodule Port do
    @moduledoc """
    A separate http port so that we can expose metrics using our 
    exporter module
    """

    def start_link(%{"name" => name, "spec" => %{"port" => port}}) do
      dispatch_rules = [
        {"/metrics", Exporter, []}
      ]

      dispatch =
        :cowboy_router.compile([
          {:_, dispatch_rules}
        ])

      res =
        :cowboy.start_clear(
          name,
          %{num_acceptors: :erlang.system_info(:schedulers), socket_opts: [port: port]},
          %{:env => %{:dispatch => dispatch}}
        )

      IO.inspect(metrics: name, port: port)
      res
    end

    def child_spec(%{"name" => name} = spec) do
      %{
        id: name,
        start: {__MODULE__, :start_link, [spec]}
      }
    end
  end

  defmodule Exporter do
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
