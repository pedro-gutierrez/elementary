defmodule Elementary.StateMachine do
  @moduledoc false

  defmacro __using__(name: name, callback: cb) do
    {:ok, settings} = cb.settings()
    {:ok, model, cmds} = cb.init(settings)

    opts = [cb: cb, model: model, cmds: cmds, settings: settings]

    quote do
      @name unquote(name)
      def name(), do: @name

      @cb unquote(opts[:cb])

      @model unquote(Macro.escape(model))
      @cmds unquote(Macro.escape(cmds))

      def cb(), do: @cb
      def permanent(), do: false

      def start_link(args) do
        GenStateMachine.start_link(__MODULE__, args)
      end

      def update(pid, effect, data) do
        GenStateMachine.cast(pid, {:update, effect, data})
      end

      def terminate(pid) do
        GenStateMachine.cast(pid, :terminate)
      end

      use GenStateMachine, callback_mode: :state_functions
      defstruct owner: :undef, model: %{}

      @impl true
      def init(owner) when is_pid(owner) do
        case apply_cmds(@cmds, @model) do
          :ok ->
            {:ok, :ready, %__MODULE__{owner: owner, model: @model}}

          {:error, e} ->
            {:stop, {:shutdown, e}}
        end
      end

      def ready(:cast, {:update, effect, data}, state) do
        with {:ok, event, decoded} <- @cb.decode(effect, data, state.model),
             {:ok, model, cmds} <- @cb.update(event, decoded, state.model),
             model <- Map.merge(state.model, model),
             :ok <- apply_cmds(cmds, model) do
          {:keep_state, %{state | model: model}}
        else
          {:error, e} ->
            state.owner |> send(e)
            {:keep_state, state}
        end
      end

      def ready(:cast, :terminate, state) do
        {:stop, :normal, state}
      end

      defp apply_cmds([], _), do: :ok

      defp apply_cmds(cmds, model) do
        Enum.reduce_while(cmds, [], fn
          {eff, enc} = cmd, acc ->
            case @cb.encode(enc, model, model) do
              {:ok, encoded} ->
                {:cont, [{eff, encoded} | acc]}

              {:error, _} = e ->
                {:halt, e}
            end

          eff, acc ->
            {:cont, [{eff, %{}} | acc]}
        end)
        |> case do
          {:error, _} = e ->
            e

          cmds ->
            cmds
            |> Enum.reverse()
            |> Enum.each(fn {effect, params} ->
              effect_apply(effect, params, self())
            end)

            :ok
        end
      end

      defp effect_apply(:response, params, owner) do
        send(owner, params)
      end

      defp effect_apply(:terminate, _, owner) do
        __MODULE__.terminate(owner)
      end
    end
  end
end
