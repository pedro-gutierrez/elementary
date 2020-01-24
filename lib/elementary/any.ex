defmodule Elementary.Any do
  @moduledoc false

  use Elementary.Provider

  alias Elementary.Kit

  defstruct kind: ""

  def parse(%{"any" => kind}, _) do
    {:ok, %__MODULE__{kind: kind}}
  end

  def parse(spec, _) do
    Kit.error(:not_supported, spec)
  end

  def decoder_ast(%{kind: "dict"}, lv) do
    {var, lv} = lv |> Kit.new_var()
    {{:var, var}, [{:call, :is_map, [{:var, var}]}], {:var, var}, lv}
  end

  def decoder_ast(%{kind: "list"}, lv) do
    {var, lv} = lv |> Kit.new_var()
    {{:var, var}, [{:call, :is_list, [{:var, var}]}], {:var, var}, lv}
  end

  def decoder_ast(%{kind: "text"}, lv) do
    {var, lv} = lv |> Kit.new_var()
    {{:var, var}, [{:call, :is_binary, [{:var, var}]}], {:var, var}, lv}
  end

  def decoder_ast(%{kind: "number"}, lv) do
    {var, lv} = lv |> Kit.new_var()
    {{:var, var}, [{:call, :is_number, [{:var, var}]}], {:var, var}, lv}
  end

  def decoder_ast(%{kind: "data"}, lv) do
    {var, lv} = lv |> Kit.new_var()
    {{:var, var}, [{:call, :is_binary, [{:var, var}]}], {:var, var}, lv}
  end
end
