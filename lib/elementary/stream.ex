defmodule Elementary.Stream do
  @moduledoc false

  use Elementary.Provider
  alias(Elementary.{Kit})

  defstruct rank: :high,
            name: "",
            version: "1",
            app: nil

  def parse(
        %{"version" => version, "kind" => "stream", "name" => name},
        _
      ) do
    name = String.to_atom(name)

    {:ok,
     %__MODULE__{
       name: name,
       version: version,
       app: name
     }}
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def ast(stream, _) do
    mod_name = Kit.camelize([stream.name, "Stream"])
    app_name = Elementary.App.app_name(stream.app)
    store_name = Elementary.Store.store_name(stream.name)

    [
      {:module, mod_name,
       [
         {:fun, :kind, [], :stream},
         {:fun, :name, [], {:symbol, stream.name}},
         {:fun, :supervised, [], {:boolean, true}},
         {:usage, __MODULE__,
          [
            store: store_name,
            stream: stream.name,
            app: app_name
          ]}
       ]}
    ]
  end

  defmacro __using__(opts) do
    quote do
      require Logger
      use GenServer

      @store unquote(opts[:store])
      @stream unquote(opts[:stream])
      @app unquote(opts[:app])

      def start_link(_) do
        GenServer.start_link(__MODULE__, nil, name: __MODULE__)
      end

      @impl true
      def init(_) do
        ref =
          @store
          |> Process.whereis()
          |> Process.monitor()

        @store.stream(fn doc ->
          with {:ok, event, %{"kind" => kind, "event" => event} = decoded} <-
                 @app.decode(@stream, doc, nil),
               {:ok, %{"id" => id}} <- @app.encode("#{kind}_#{event}_identity", decoded) do
            IO.inspect(event: event, data: decoded, id: id, kind: kind)
          else
            {:error, e} ->
              Logger.warn("#{inspect(Map.put(e, :stream, @stream))}")
          end
        end)

        {:ok, ref}
      end

      @impl true
      def handle_info({:DOWN, ref, :process, _, _}, ref) do
        Process.demonitor(ref)
        {:stop, :shutdown, nil}
      end
    end
  end
end
