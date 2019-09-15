defmodule Elementary.Lang.Any do
  @moduledoc false

  use Elementary.Provider,
    kind: "any",
    module: __MODULE__

  alias Elementary.Kit

  defstruct kind: ""

  def parse(%{"any" => kind}, _) do
    {:ok, %__MODULE__{kind: kind}}
  end

  def parse(spec, _) do
    Kit.error(:not_supported, spec)
  end

  def decoder_ast(%{kind: "dict"}, _) do
    {{:var, :map}, [{:call, :is_map, [{:var, :map}]}], {:var, :map}}
  end

  def decoder_ast(%{kind: "list"}, _) do
    {{:var, :list}, [{:call, :is_list, [{:var, :list}]}], {:var, :list}}
  end

  def decoder_ast(%{kind: "text"}, _) do
    {{:var, :text}, [{:call, :is_binary, [{:var, :text}]}], {:var, :text}}
  end
end
