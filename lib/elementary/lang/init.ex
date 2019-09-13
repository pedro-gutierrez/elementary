defmodule Elementary.Lang.Init do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit
  alias Elementary.Lang.{Model, Cmds}

  defstruct model: %Model{},
            cmds: %Cmds{}

  def parse(%{"init" => init}, providers) do
    parse_init(init, providers)
  end

  def parse(_, _) do
    {:ok, %__MODULE__{}}
  end

  def parse_init(
        %{
          "model" => model_spec,
          "cmds" => cmds_spec
        } = init,
        providers
      ) do
    with {:ok, model} <- model_spec |> Model.parse(providers),
         {:ok, cmds} <- cmds_spec |> Cmds.parse(providers) do
      {:ok, %__MODULE__{model: model, cmds: cmds}}
    else
      {:error, e} ->
        Kit.error(:parse_error, %{
          spec: init,
          reason: e
        })
    end
  end

  def parse_init(%{"model" => _} = spec, providers) do
    parse_init(Map.put(spec, "cmds", []), providers)
  end

  def parse_init(%{"cmds" => _} = spec, providers) do
    parse_init(Map.put(spec, "model", %{}), providers)
  end

  def parse_init(spec, providers) when is_map(spec) do
    parse_init(%{"model" => spec, "cmds" => []}, providers)
  end

  def ast(init, index) do
    {:props,
     [
       model: init.model.__struct__.ast(init.model, index),
       cmds: init.cmds.__struct__.ast(init.cmds, index)
     ]}
  end

  def compile(init, providers) do
    init.spec.__struct__.compile(init.spec, providers)
  end
end
