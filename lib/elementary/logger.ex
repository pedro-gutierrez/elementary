defmodule Elementary.Logger do
  use GenServer

  @name Elementary.Logger

  defmodule Fallback do
    require Logger

    def log(%{level: :error} = data) do
      Logger.error("#{inspect(data)}")
    end

    def log(%{level: :warn} = data) do
      Logger.warn("#{inspect(data)}")
    end

    def log(data) do
      Logger.info("#{inspect(data)}")
    end

    def query(_), do: {:ok, []}
  end

  def log(%{kind: _, name: _} = data) do
    data = Map.put(data, :time, DateTime.utc_now())
    GenServer.cast(@name, {:write, data})
  end

  def query(query) do
    GenServer.call(@name, {:query, query})
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: @name)
  end

  def init(_) do
    {:ok, host} = :inet.gethostname()

    mod =
      case Elementary.Index.get("logger", "default") do
        {:ok, mod} ->
          mod

        {:error, _} ->
          Elementary.Logger.Fallback
      end

    {:ok, {"#{host}", mod}}
  end

  def handle_cast({:write, data}, {host, mod} = state) do
    %{host: host, level: :info}
    |> Map.merge(data)
    |> mod.log()

    {:noreply, state}
  end

  def handle_call({:query, query}, _, {_, mod} = state) do
    data = mod.query(query)
    {:reply, data, state}
  end
end
