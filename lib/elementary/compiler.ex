defmodule Elementary.Compiler do
  @moduledoc false
  use GenServer
  alias Elementary.{Kit, Ast}

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    {:ok, pid} = Kit.watch()
    {:ok, [watcher: pid]}
  end

  def handle_info({:file_event, _, {_, [:created]}}, state) do
    {:noreply, state}
  end

  def handle_info({:file_event, _, {_, _}}, state) do
    compiled()
    {:noreply, state}
  end

  def compiled() do
    with providers <- Kit.providers(),
         {:ok, specs} <- Kit.read_yamls() |> Kit.parse_specs(providers),
         asts <- specs |> Kit.asts(),
         {:ok, mods} <- asts |> Ast.compiled() do
      {:ok, mods}
    else
      other ->
        other
    end
  end
end
