defmodule Elementary.Application do
  @moduledoc false

  use Application
  require Logger
  alias Elementary.Compiler
  alias Elementary.Kit
  alias Elementary.Effect
  alias Elementary.Settings
  alias Elementary.Playbook
  alias Elementary.Graph

  def start(_type, _args) do
    plugins = Kit.plugins()
    providers = Kit.providers(plugins)
    effects = Kit.effects(plugins)

    children =
      with {:ok, mods} <- Compiler.compiled(providers),
           {:ok, _} <- Effect.compiled(effects),
           {:ok, _} <- Settings.indexed(mods),
           {:ok, _} <- Playbook.indexed(mods),
           {:ok, _} <- Graph.indexed(mods) do
        Kit.supervised(mods)
      else
        {:error, e} ->
          IO.inspect(e)
          []
      end

    Supervisor.start_link(children ++ [{Elementary.Compiler, [providers]}, Elementary.Apps],
      strategy: :one_for_one,
      name: Elementary.Supervisor
    )
  end
end
