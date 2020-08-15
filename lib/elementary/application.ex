defmodule Elementary.Application do
  @moduledoc false

  use Application
  require Logger
  alias Elementary.{Slack, Kit}

  def start(_type, _args) do
    Logger.configure(level: :info)

    {:ok, pid} =
      Supervisor.start_link(
        [
          Elementary.Index,
          Elementary.Compiler,
          Elementary.Stores,
          # Elementary.Test,
          Elementary.Cluster,
          Elementary.Services,
          Elementary.Streams,
          Elementary.Ports
        ],
        strategy: :one_for_one,
        name: Elementary.Supervisor
      )

    Slack.notify("cluster", "Server did start", %{
      host: Kit.hostname()
    })

    {:ok, pid}
  end
end
