defmodule Elementary.Compiler do
  @moduledoc false
  use GenServer
  alias Elementary.{Kit, Ast}
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init([providers]) do
    {:ok, pid} = Kit.watch()
    {:ok, [watcher: pid, providers: providers]}
  end

  def handle_info({:file_event, _, {_, [:created]}}, state) do
    {:noreply, state}
  end

  def handle_info({:file_event, _, {_, _}}, state) do
    compiled(state[:providers])
    {:noreply, state}
  end

  def compiled(providers) do
    with specs <- Kit.read_yamls(),
         {:ok, specs} <- Kit.parse_specs(specs, providers),
         asts <- specs |> Kit.asts(),
         {:ok, mods} <- asts |> Ast.compiled() do
      {:ok, mods}
    else
      {:error, _} = e ->
        e
    end
  end
end
