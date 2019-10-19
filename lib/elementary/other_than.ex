defmodule Elementary.OtherThan do
  @moduledoc false

  use Elementary.Provider

  alias Elementary.Kit

  defstruct spec: nil

  def parse(%{"other_than" => value}, _) do
    {:ok, %__MODULE__{spec: value}}
  end

  def parse(spec, _) do
    Kit.error(:not_supported, spec)
  end

  def decoder_ast(%{spec: value}, lv) do
    {var, lv} = lv |> Kit.new_var()
    {{:var, var}, [{:other_than, [{:var, var}], value}], {:var, var}, lv}
  end
end
