defmodule Elementary.Lang.Key do
  @moduledoc false

  use Elementary.Provider,
    kind: "key",
    module: __MODULE__

  alias Elementary.Kit

  defstruct key: "", in: :undef

  def parse(%{"key" => key} = spec, _providers) do
    parsed = %__MODULE__{key: key}

    case Map.has_key?(spec, "in") do
      true ->
        {:ok, %{parsed | in: Map.get(spec, "in")}}

      false ->
        {:ok, parsed}
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def ast(%{key: key}, _) do
    {:case, {:call, :Map, :get, [{:var, :data}, {:text, key}, :undefined]},
     [
       {:clause, :undefined, {:error, :missing_key, key, {:var, :data}}},
       {:clause, {:var, :value}, {:ok, {:var, :value}}}
     ]}
  end
end
