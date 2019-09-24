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

      def update(pid, data) do
        GenStateMachine.cast(pid, {:update, data})
      end

      def terminate(pid) do
        GenStateMachine.cast(pid, :terminate)
      end

      use GenStateMachine, callback_mode: :state_functions
      defstruct owner: :undef, model: %{}

      @impl true
      def init(owner) when is_pid(owner) do
        [model: model, cmds: cmds] = @cb.init()
        {:ok, :ready, %__MODULE__{owner: owner, model: model}}
      end

      def ready(:cast, {:update, data}, state) do
        case @cb.decode("default", data, state.model) do
          {:ok, event, decoded} ->
            case @cb.update(event, decoded, state.model) do
              {:ok, model, _cmds} ->
                send(state.owner,
                  status: 201,
                  headers: %{"content-type" => "application/json"},
                  body: model
                )

                {:keep_state, %{state | model: model}}

              {:error, e} ->
                state.owner |> send(e)
                {:keep_state, state}
            end

          {:error, e} ->
            state.owner |> send(e)
            {:keep_state, state}
        end
      end

      def ready(:cast, :terminate, state) do
        {:stop, :normal, state}
      end
    end
  end
end
