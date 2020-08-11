defmodule Elementary.Application do
  @moduledoc false

  use Application
  require Logger

  def start(_type, _args) do
    Logger.configure(level: :info)

    {:ok, pid} =
      Supervisor.start_link(
        [
          Elementary.Index,
          Elementary.Compiler,
          # Elementary.Test,
          Elementary.Logger,
          Elementary.Cluster,
          Elementary.Stores,
          Elementary.Services,
          Elementary.Streams,
          Elementary.Ports
        ],
        strategy: :one_for_one,
        name: Elementary.Supervisor
      )

    {:ok, pid}
  end
end
