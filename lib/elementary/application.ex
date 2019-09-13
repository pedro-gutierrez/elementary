defmodule Elementary.Application do
  @moduledoc false

  use Application
  alias Elementary.Compiler
  alias Elementary.Kit

  def start(_type, _args) do
    {:ok, mods} = Compiler.compiled()
    children = mods |> Kit.supervised()

    Supervisor.start_link(children ++ [Elementary.Compiler, Elementary.Apps],
      strategy: :one_for_one,
      name: Elementary.Supervisor
    )
  end
end
