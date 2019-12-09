defmodule Elementary.Effects.Graph do
  @moduledoc false

  use Elementary.Effect, :graph
  alias Elementary.Index.Graph

  def effect(owner, %{"graph" => graph, "query" => query}) do
    with {:ok, schema} <- Graph.get(graph),
         {:ok, query} <- parse(query),
         {time, {:ok, result}} <-
           :timer.tc(fn ->
             Absinthe.run(
               query,
               schema
             )
           end) do
      %{
        "status" => "ok",
        "data" => result,
        "time" => time
      }
    else
      {:error, reason} ->
        %{"status" => "error", "reason" => reason}
    end
    |> update(owner)
  end

  def parse(query) when is_binary(query) do
    case Jason.decode(query) do
      {:ok, %{"query" => q}} ->
        {:ok, q}

      {:error, _} ->
        {:ok, query}
    end
  end
end
