defmodule Elementary.Index do
  @moduledoc false
  use GenServer

  @table :elementary

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def put(spec) do
    true = GenServer.call(__MODULE__, {:write, spec})
  end

  def specs(kind) do
    :ets.match(@table, {{kind, :_}, :"$1"})
    |> List.flatten()
  end

  @spec spec(String.t(), String.t()) :: {:ok, map()} | :not_found
  def spec(kind, name) do
    case :ets.lookup(@table, {kind, name}) do
      [{_, spec}] -> {:ok, spec}
      [] -> :not_found
    end
  end

  @spec spec!(any, any) :: any
  def spec!(kind, name) do
    case spec(kind, name) do
      {:ok, spec} ->
        spec

      :not_found ->
        raise "no such spec \"#{name}\" of kind \"#{kind}\""
    end
  end

  @impl true
  def init(_) do
    @table = :ets.new(@table, [:named_table, {:read_concurrency, true}])
    {:ok, []}
  end

  @impl true
  def handle_call({:write, %{"kind" => kind, "name" => name} = spec}, _, state) do
    res = :ets.insert(@table, {{kind, name}, spec})
    {:reply, res, state}
  end
end
