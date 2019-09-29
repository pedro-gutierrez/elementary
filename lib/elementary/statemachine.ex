defmodule Elementary.StateMachine do
  @moduledoc false

  defmacro __using__(name: name, callback: cb) do
    quote do
      @name unquote(name)
      def name(), do: @name

      @cb unquote(cb)
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

      def respond(pid, data) do
        GenStateMachine.cast(pid, {:respond, data})
      end

      use GenStateMachine, callback_mode: :state_functions
      defstruct owner: :undef, model: %{}

      @impl true
      def init(owner) when is_pid(owner) do
        {:ok, model, _cmds} = @cb.init()
        {:ok, :ready, %__MODULE__{owner: owner, model: model}}
      end

      def ready(:cast, {:update, effect, data}, state) do
        with {:ok, event, decoded} <- @cb.decode(effect, data, state.model),
             {:ok, model, cmds} <- @cb.update(event, decoded, state.model),
             {:ok, cmds} <- encoded_cmds(cmds, model),
             :ok <- apply_cmds(cmds) do
          {:keep_state, %{state | model: model}}
        else
          {:error, e} ->
            state.owner |> send(e)
            {:keep_state, state}
        end
      end

      def ready(:cast, {:respond, data}, state) do
        send(state.owner, data)
        {:keep_state, state}
      end

      def ready(:cast, :terminate, state) do
        {:stop, :normal, state}
      end

      defp encoded_cmds(cmds, model) do
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
            {:ok, Enum.reverse(cmds)}
        end
      end

      defp apply_cmds(cmds) do
        Enum.each(cmds, fn {effect, params} ->
          effect_apply(effect, params, self())
        end)
      end

      defp effect_apply(:response, params, owner) do
        __MODULE__.respond(owner, params)
      end

      defp effect_apply(:terminate, _, owner) do
        __MODULE__.terminate(owner)
      end
    end
  end
end
