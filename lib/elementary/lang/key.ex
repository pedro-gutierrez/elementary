defmodule Elementary.Lang.Key do
  @moduledoc false

  use Elementary.Provider
  alias Elementary.Kit

  defstruct key: nil, in: nil

  def parse(%{"key" => k, "in" => i}, _) do
    {:ok, %__MODULE__{key: k, in: i}}
  end

  def parse(%{"key" => k}, _) do
    {:ok, %__MODULE__{key: k}}
  end

  def parse("@", _) do
    {:ok, %__MODULE__{}}
  end

  def parse("@" <> path, _) do
    {:ok,
     String.split(path, ".")
     |> Enum.reverse()
     |> Enum.reduce(%__MODULE__{}, fn
       k, %{key: nil} = acc ->
         %__MODULE__{acc | key: k}

       k, %{in: nil} = acc ->
         %__MODULE__{acc | in: k}

       k, acc ->
         put_key_in(k, acc)
     end)}
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  defp put_key_in(k, %__MODULE__{in: i} = acc) when is_binary(i) do
    %{acc | in: %__MODULE__{key: i, in: k}}
  end

  defp put_key_in(k, %__MODULE__{in: i} = acc) when is_map(i) do
    %{acc | in: put_key_in(k, i)}
  end

  def ast(%__MODULE__{key: nil, in: nil}, _) do
    {:ok, {:var, :data}}
  end

  def ast(%__MODULE__{key: key, in: nil}, _) do
    ast_for_key(key, :data)
  end

  def ast(%__MODULE__{key: key, in: i}, index) when is_binary(i) do
    {:let, [v: ast(%__MODULE__{key: i}, index)], ast_for_key(key, :v)}
  end

  def ast(%__MODULE__{key: key, in: i}, index) when is_map(i) do
    {:let, [v: ast(i, index)], ast_for_key(key, :v)}
  end

  defp ast_for_key(key, context) do
    {:case, {:var, context},
     [
       {{:map, [{{:text, key}, {:var, :v}}]}, {:ok, {:var, :v}}},
       {{:var, :_}, {:error, :missing_key, {:text, key}, {:var, context}}}
     ]}
  end

  def literal?(_), do: false
end
