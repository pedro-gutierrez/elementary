defmodule Elementary.Number do
  @moduledoc false

  use Elementary.Provider,
    kind: "number",
    module: __MODULE__

  alias Elementary.Kit

  defstruct spec: %{}

  def parse(%{"number" => spec}, _providers) when is_number(spec) do
    ok(spec)
  end

  def parse(%{"number" => spec}, _providers) when is_binary(spec) do
    case Float.parse(spec) do
      {num, _} ->
        ok(num)

      :error ->
        Kit.error(:not_supoorted, spec)
    end
  end

  def parse(spec, _providers) when is_number(spec) do
    ok(spec)
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  defp ok(number) do
    {:ok, %__MODULE__{spec: number}}
  end

  def ast(number, _) do
    {:ok, {:number, number.spec}}
  end

  def literal?(_) do
    true
  end
end
