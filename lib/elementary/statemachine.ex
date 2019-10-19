defmodule Elementary.StateMachine do
  @moduledoc false

  defmacro __using__(cb) do
    {:ok, settings} = cb.settings()
    {:ok, model, cmds} = cb.init(settings)

    opts = [cb: cb, model: model, cmds: cmds, settings: settings]

    quote do
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

      def reply(pid, data) do
        GenStateMachine.cast(pid, {:reply, data})
      end

      def terminate(pid) do
        GenStateMachine.cast(pid, :terminate)
      end

      use GenStateMachine, callback_mode: :state_functions
      defstruct owner: nil, model: %{}

      @impl true
      def init(owner) when is_pid(owner) do
        case apply_cmds(@cmds, @model) do
          :ok ->
            {:ok, :ready, %__MODULE__{owner: owner, model: @model}}

          {:error, e} ->
            send(owner, e)
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
            send(state.owner, e)
            {:stop, {:shutdown, e}}
        end
      end

      def ready(:cast, :terminate, state) do
        {:stop, :normal, state}
      end

      def ready(:cast, {:reply, data}, state) do
        send(state.owner, data)
        {:keep_state, state}
      end

      defp apply_cmds([], _), do: :ok

      defp apply_cmds([{eff, enc} | rem], model) do
        with {:ok, encoded} <- @cb.encode(enc, model),
             :ok <- Elementary.Effects.apply(eff, self(), encoded) do
          apply_cmds(rem, model)
        else
          {:error, _} = e ->
            e
        end
      end

      defp apply_cmds([eff | rem], model) do
        case Elementary.Effects.apply(eff, self(), nil) do
          :ok ->
            apply_cmds(rem, model)

          {:error, _} = e ->
            e
        end
      end
    end
  end
end
