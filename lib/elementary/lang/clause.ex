defmodule Elementary.Lang.Clause do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit
  alias Elementary.Lang.{Condition, Model, Cmds}

  defstruct condition: nil,
            model: nil,
            cmds: nil

  def parse(
        %{"when" => condition, "model" => model, "cmds" => cmds} = raw,
        providers
      ) do
    with {:ok, condition} <- Condition.parse(condition, providers),
         {:ok, model} <- Model.parse(model, providers),
         {:ok, cmds} <-
           Cmds.parse(cmds, providers) do
      {:ok,
       %__MODULE__{
         condition: condition,
         model: model,
         cmds: cmds
       }}
    else
      {:error, e} ->
        Kit.error(:parse_error, %{
          spec: raw,
          reason: e
        })
    end
  end

  def parse(%{"model" => _, "cmds" => _} = raw, providers) do
    raw
    |> Map.put("when", Condition.default())
    |> parse(providers)
  end

  def parse(%{"cmds" => _} = raw, providers) do
    raw
    |> Map.put("model", Model.default())
    |> parse(providers)
  end

  def parse(%{"model" => _} = raw, providers) do
    raw
    |> Map.put("cmds", Cmds.default())
    |> parse(providers)
  end

  def parse(model, providers) when is_map(model) do
    parse(%{"model" => model}, providers)
  end

  def parse(spec, _) do
    Kit.error(:not_supported, spec)
  end

  def ast(%{condition: :none} = spec, index) do
    ast(%{spec | condition: true}, index)
  end

  def ast(clause, index) do
    model_ast = clause.model.__struct__.ast(clause.model, index)
    cmds_ast = clause.cmds.__struct__.ast(clause.cmds, index)

    case {literal_model?(clause), literal_cmds?(clause)} do
      {true, true} ->
        {:ok, model} = model_ast
        {:ok, cmds} = cmds_ast
        {:clause, {:boolean, true}, {:ok, model, cmds}}

      {true, false} ->
        {:ok, model} = model_ast

        {:clause, {:boolean, true},
         {:let,
          [
            {:cmds, cmds_ast}
          ], {model, {:var, :cmds}}}}

      {false, true} ->
        {:ok, cmds} = cmds_ast

        {:clause, {:boolean, true},
         {:let,
          [
            {:model, model_ast}
          ], {:var, :model}, cmds}}

      {false, false} ->
        {:clause, {:boolean, true},
         {:let,
          [
            {:model, model_ast},
            {:cmds, cmds_ast}
          ]}}
    end
  end

  defp literal_model?(clause) do
    clause.model.__struct__.literal?(clause.model)
  end

  defp literal_cmds?(clause) do
    clause.cmds.__struct__.literal?(clause.cmds)
  end
end
