defmodule Elementary.StateMachine do
  @moduledoc false

  defmacro __using__(name: name) do
    quote do
      @name unquote(name)
      def name(), do: @name
      def permanent(), do: false

      def start_link(args) do
        GenStateMachine.start_link(__MODULE__, args)
      end

      def update(pid, data) do
        GenStateMachine.cast(pid, {:update, data})
      end

      use GenStateMachine, callback_mode: :state_functions
      defstruct owner: :undef, data: %{}

      @impl true
      def init(owner) when is_pid(owner) do
        {:ok, :ready, %__MODULE__{owner: owner}}
      end

      def ready(:cast, {:update, data}, state) do
        send(state.owner,
          status: 201,
          headers: %{"content-type" => "application/json"},
          body: %{"goodbye" => "john"}
        )

        {:stop, :normal, state}
      end
    end
  end
end
