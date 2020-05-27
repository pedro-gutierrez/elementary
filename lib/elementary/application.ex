defmodule Elementary.Application do
  @moduledoc false

  use Application
  require Logger

  alias Elementary.{
    Compiler
  }

  @kinds_to_boot ["port", "store"]

  def start(_type, _args) do
    Code.compiler_options(ignore_module_conflict: true)

    mods = Compiler.compile()

    children =
      Enum.filter(mods, fn mod ->
        Enum.member?(@kinds_to_boot, mod.kind())
      end)

    Logger.configure(level: :info)

    {:ok, pid} =
      Supervisor.start_link(children ++ [Elementary.Compiler, Elementary.Test, Elementary.Logger],
        strategy: :one_for_one,
        name: Elementary.Supervisor
      )

    # Store.init_all()
    {:ok, pid}
  end
end
