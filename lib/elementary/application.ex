defmodule Elementary.Application do
  @moduledoc false

  use Application
  alias Elementary.Compiler
  alias Elementary.Kit

  def start(_type, _args) do
    children =
      case Compiler.compiled() do
        {:ok, mods} ->
          Kit.supervised(mods)

        {:error, e} ->
          []
      end

    Supervisor.start_link(children ++ [Elementary.Compiler, Elementary.Apps],
      strategy: :one_for_one,
      name: Elementary.Supervisor
    )
  end
end
