defmodule Elementary.Effect do
  @moduledoc false

  @callback effect(map(), pid()) :: :ok | {:error, any()}

  def compiled(mods) do
    {:module, Elementary.Effects,
     Enum.map(mods, fn m ->
       {:fun, :apply, [{:symbol, m.name()}, :owner, :data],
        {:call, m, :effect, [{:var, :owner}, {:var, :data}]}}
     end) ++
       [
         {:fun, :apply, [{:var, :effect}, :_owner, :_data],
          {:tuple, [:error, {:map, [{:no_such_effect, {:var, :effect}}]}]}}
       ]}
    |> Elementary.Ast.compiled()
  end

  defmacro __using__(name) do
    quote do
      @behaviour Elementary.Effect

      @name unquote(name)
      def name(), do: @name

      defp update(data, pid) do
        GenStateMachine.cast(pid, {:update, @name, data})
      end

      defp reply(data, pid) do
        GenStateMachine.cast(pid, {:reply, data})
      end

      defp terminate(pid) do
        GenStateMachine.cast(pid, :terminate)
      end
    end
  end
end
