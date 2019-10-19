defmodule Elementary.Encoder do
  @moduledoc false

  use Elementary.Provider

  alias Elementary.Kit

  defstruct spec: %{}

  def default(), do: %__MODULE__{}

  def parse(%{"encoder" => name}, _) when is_binary(name) do
    {:ok, %__MODULE__{spec: name}}
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def ast(%{spec: name}, _) when is_binary(name) do
    {:call, :encode, [{:symbol, name}, {:var, :data}]}
  end

  def literal?(_), do: false
end
