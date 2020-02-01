defmodule Elementary.Application do
  @moduledoc false

  use Application
  require Logger

  alias Elementary.{
    Kit,
    Compiler
  }

  def start(_type, _args) do
    Code.compiler_options(ignore_module_conflict: true)

    mods = Compiler.compile()

    children = Enum.filter(mods, &Kit.defines_child_spec?(&1))

    Logger.configure(level: :info)

    {:ok, pid} =
      Supervisor.start_link(children ++ [Elementary.Compiler],
        strategy: :one_for_one,
        name: Elementary.Supervisor
      )

    # Store.init_all()
    {:ok, pid}
  end

  ##  {:ok, mod} =
  ##    Kit.defmod(
  ##      Elementary.Cache,
  ##      Enum.map(specs, fn %{"kind" => kind, "name" => name} = spec ->
  ##        quote do
  ##          def get(unquote(kind), unquote(name)), do: unquote(Macro.escape(spec))
  ##        end
  ##      end)
  ##    )
end
