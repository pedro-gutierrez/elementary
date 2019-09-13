defmodule Elementary.Lang.Clause do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit
  alias Elementary.Lang.{Condition, Model, Cmds}

  defstruct [
    spec: %{
      condition: :none,
      model: :none,
      cmds: :none
    }
  ]

  def parse(raw, providers) do
    with clause <- %__MODULE__{},
      {:ok, clause } <- maybe_with(clause, raw, providers, :condition, Condition),
      {:ok, clause } <- maybe_with(clause, raw, providers, :model, Model),
      {:ok, clause } <- maybe_with(clause, raw, providers, :cmds, Cmds) do

      {:ok, clause}
    else
      {:error, e} ->
        Kit.error(:parse_error, %{
          spec: raw,
          reason: e
        })
    end
  end

  defp maybe_with(%{spec: spec}=clause, raw, providers, section, parser) do
    case raw |> parser.parse(providers) do
      {:ok, parsed} ->
        {:ok, %{clause | spec: Map.put(spec, section, parsed)}}

      {:error, e} ->
        Kit.error(:parse_error, %{
          section: section,
          reason: e
        })
    end
  end

  def ast(%{condition: :none}=spec, index) do
    ast(%{spec | condition: true}, index)
  end

    def ast(clause, index) do
    {:clause,
      {:boolean, true},
      {:props, [
          model: clause.spec.model.__struct__.ast(clause.spec.model, index),
        cmds: []]}}
  end
end
