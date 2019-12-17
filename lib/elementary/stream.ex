defmodule Elementary.Stream do
  @moduledoc false

  use Elementary.Provider
  alias(Elementary.{Kit})

  defstruct rank: :high,
            name: "",
            version: "1",
            app: nil,
            store: nil,
            topic: nil,
            replay: false

  def parse(
        %{
          "version" => version,
          "kind" => "stream",
          "name" => name,
          "spec" => %{"store" => store, "topic" => topic, "replay" => replay}
        },
        _
      ) do
    name = String.to_atom(name)
    store = String.to_atom(store)
    topic = String.to_atom(topic)

    {:ok,
     %__MODULE__{
       name: name,
       version: version,
       app: store,
       store: store,
       topic: topic,
       replay: replay
     }}
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def ast(stream, _) do
    [
      {:module, Kit.camelize([stream.name, "Stream"]),
       [
         {:fun, :kind, [], :stream},
         {:fun, :name, [], {:symbol, stream.name}},
         {:fun, :supervised, [], {:boolean, true}},
         {:usage, __MODULE__,
          [
            store: Elementary.Store.store_name(stream.store),
            stream: stream.app,
            app: Elementary.App.app_name(stream.app),
            topic: stream.topic,
            replay: stream.replay
          ]}
       ]}
    ]
  end

  defmacro __using__(opts) do
    quote do
      require Logger
      use GenServer

      @replay unquote(opts[:replay])
      @topic unquote(opts[:topic])
      @store unquote(opts[:store])
      @stream unquote(opts[:stream])
      @app unquote(opts[:app])
      @app_state_machine unquote(Elementary.App.state_machine_name(opts[:stream]))

      def start_link(_) do
        GenServer.start_link(__MODULE__, nil, name: __MODULE__)
      end

      @impl true
      def init(_) do
        {:ok, nil, {:continue, :listen}}
      end

      @impl true
      def handle_continue(:listen, nil) do
        ref =
          @store
          |> Process.whereis()
          |> Process.monitor()

        case @replay do
          true ->
            @store.replay(&activate(&1), @topic)

          false ->
            @store.watch(&activate(&1), @topic)
        end

        {:noreply, ref}
      end

      @impl true
      def handle_info({:DOWN, ref, :process, _, _}, ref) do
        Process.demonitor(ref)
        {:stop, :shutdown, nil}
      end

      alias Elementary.Entity

      def activate(%{"kind" => kind, "id" => id} = data) do
        {:ok, pid} = Entity.activate(kind, id)
        Entity.update(pid, data)
      end
    end
  end
end
