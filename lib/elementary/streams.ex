defmodule Elementary.Streams do
  @moduledoc false

  use Supervisor
  alias Elementary.{Index, Streams.Stream}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    Index.specs("stream")
    |> Enum.map(&service_spec(&1))
    |> Supervisor.init(strategy: :one_for_one)
  end

  defp service_spec(spec) do
    {Elementary.Streams.Stream, spec}
  end

  def info() do
    "stream"
    |> Index.specs()
    |> Enum.map(&Stream.info(&1))
  end

  defmodule Stream do
    use GenServer
    alias Elementary.{Index, App, Stores.Store, Services.Service}
    require Logger

    def name(%{"name" => name}), do: name(name)
    def name(name), do: String.to_atom("#{name}_stream")

    def info(%{"name" => name} = spec) do
      registered_name = name(spec)
      case :global.whereis_name(registered_name) do
        :undefined  ->
          %{name: name}
        pid ->
          GenServer.call(pid, :info)
      end
    end

    def start_link(spec) do
      name = name(spec)
      GenServer.start_link(__MODULE__, spec, name: name)
    end

    @impl true
    def init(%{"name" => name, "spec" => %{"apps" => apps, "collection" => col}} = spec) do
      registered_name = name(spec)
      %{"store" => store} = App.settings!(spec)

      initial_state = %{
        stream: name,
        registered_name: registered_name,
        store: store,
        col: col,
        apps: apps,
        subscription: nil,
        offset: ""
      }

      {:ok, initial_state, {:continue, :register}}
    end

    @impl true
    def handle_continue(:register, %{registered_name: name, stream: stream} = state) do
      case :global.register_name(name, self()) do
        :yes ->
          {:noreply, state, {:continue, :subscribe}}

        _ ->
          case :global.whereis_name(name) do
            :undefined ->
              {:noreply, state, {:continue, :register}}

            pid when is_pid(pid) ->
              ref = Process.monitor(pid)
              IO.inspect(stream: stream, status: :waiting, for: pid, from: node(pid))
              {:noreply, Map.put(state, :leader, ref)}
          end
      end
    end

    def handle_continue(:subscribe, %{store: store, stream: stream, registered_name: stream_name, col: col} = state) do
      offset = read_offset(state)

      data_fn = fn data ->
        GenServer.cast({:global, stream_name}, data)
      end

      {:ok, pid} = Store.subscribe(store, col, %{"offset" => offset}, data_fn)

      IO.inspect(stream: stream, status: :subscribed)
      {:noreply, %{state | offset: offset, subscription: pid}}
    end

    @impl true
    def handle_info({:DOWN, ref, :process, _, _}, %{leader: ref} = state) do
      {:noreply, state, {:continue, :register}}
    end

    def handle_info(other, state) do
      Logger.warn("unexpected info message #{inspect(other)} in #{inspect(state)}")
      {:noreply, state}
    end

    @impl true
    def handle_cast(%{"offset" => offset}, state) do
      {:noreply, %{state | offset: offset}}
    end

    @impl true
    def handle_cast(%{"data" => data}, %{store: store, apps: apps} = state) do
      :ok =
        Enum.each(apps, fn app ->
          with {:error, e} <- Service.run(app, "caller", data) do
            error = Map.merge(e, %{"app" => app, "timestamp" => DateTime.utc_now()})
            store = Index.spec!("store", store)
            Store.insert(store, "errors", error, logs: :disable)
          end
        end)

      :ok = write_offset(state)
      {:noreply, state}
    end

    @impl true
    def handle_call(:info, _, state) do
      {:reply, stream_info(state), state}
    end

    def stop(reason, %{stream: stream} = state) do
      Logger.warn("stopped stream #{stream} (#{inspect(self())}): #{reason}")
      {:ok, state}
    end

    defp read_offset(%{store: store, stream: stream}) do
      case "store" |> Index.spec!(store) |> Store.find_one("streams", %{"id" => stream}) do
        {:ok, %{"offset" => offset}} ->
          offset

        {:error, :not_found} ->
          ""
      end
    end

    defp write_offset(%{store: store, stream: stream, offset: offset}) do
      store = Index.spec!("store", store)

      case Store.ensure(store, "streams", %{"id" => stream}, %{
             "offset" => offset,
             "tick" => DateTime.utc_now(),
             "node" => Node.self()
           }) do
        {:ok, 1} ->
          :ok

        {:error, e} ->
          Logger.error("Error updating offset: #{inspect(e)}")
          :ok
      end
    end

    defp stream_info(%{stream: stream}) do
      %{name: stream, node: Node.self()}
    end
  end
end
