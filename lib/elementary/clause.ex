defmodule Elementary.Clause do
  @moduledoc false

  use Elementary.Provider
  alias Elementary.{Kit, Condition, Model, Cmds}

  defstruct condition: nil,
            model: nil,
            cmds: nil

  def default() do
    %__MODULE__{
      condition: true,
      model: Model.default(),
      cmds: Cmds.default()
    }
  end

  def parse(
        %{"when" => _, "model" => _, "cmds" => _} = raw,
        providers
      ) do
    with {:ok, condition} <- Condition.parse(raw, providers),
         {:ok, model} <- Model.parse(raw, providers),
         {:ok, cmds} <-
           Cmds.parse(raw, providers) do
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
    |> Map.put("when", true)
    |> parse(providers)
  end

  def parse(%{"cmds" => _} = raw, providers) do
    raw
    |> Map.put("model", %{})
    |> parse(providers)
  end

  def parse(%{"model" => _} = raw, providers) do
    raw
    |> Map.put("cmds", [])
    |> parse(providers)
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
    {:clause, {:boolean, true}, [model: model_ast, cmds: cmds_ast]}
  end
end
