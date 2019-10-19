defmodule Elementary.Boolean do
  @moduledoc false

  use Elementary.Provider
  alias Elementary.Kit

  defstruct spec: %{}

  def parse(%{"boolean" => value}, _providers) when is_boolean(value) do
    ok(value)
  end

  def parse(value, _providers) when is_boolean(value) do
    ok(value)
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  defp ok(value) do
    {:ok, %__MODULE__{spec: value == true}}
  end

  def ast(boolean, _) do
    {:ok, {:boolean, boolean.spec}}
  end

  def literal?(_) do
    true
  end
end
