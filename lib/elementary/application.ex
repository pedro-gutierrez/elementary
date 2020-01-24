defmodule Elementary.Application do
  @moduledoc false

  use Application
  require Logger

  alias Elementary.{
    Compiler,
    Kit,
    Effect,
    App,
    Settings,
    Playbook,
    Store,
    Entity
  }

  def start(_type, _args) do
    Code.compiler_options(ignore_module_conflict: true)

    plugins = Kit.plugins()
    providers = Kit.providers(plugins)
    effects = Kit.effects(plugins)

    IO.inspect(yamls: Kit.read_yamls())

    children =
      with {:ok, mods} <- Compiler.compiled(providers),
           {:ok, _} <- Effect.indexed(effects),
           {:ok, _} <- Settings.indexed(mods),
           {:ok, _} <- App.indexed(mods),
           {:ok, _} <- Playbook.indexed(mods),
           {:ok, _} <- Store.indexed(mods),
           {:ok, _} <- Entity.indexed(mods) do
        Kit.supervised(mods)
      else
        {:error, e} ->
          IO.inspect(e)
          []
      end

    children = [
      {Registry,
       [
         keys: :unique,
         name: Apps
       ]}
      | children
    ]

    Logger.configure(level: :info)

    {:ok, pid} =
      Supervisor.start_link(children ++ [{Elementary.Compiler, [providers]}, Elementary.Apps],
        strategy: :one_for_one,
        name: Elementary.Supervisor
      )

    Store.init_all()
    {:ok, pid}
  end
end
