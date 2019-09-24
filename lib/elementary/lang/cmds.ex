defmodule Elementary.Lang.Cmds do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit
  alias Elementary.Lang.Cmd

  defstruct spec: []

  def default() do
    []
  end

  def parse(specs, providers) when is_map(specs) do
    specs
    |> Enum.reduce([], fn {effect, encoder}, acc ->
      [%{"effect" => effect, "encoder" => encoder} | acc]
    end)
    |> parse(providers)
  end

  def parse(specs, providers) when is_list(specs) do
    case parse_cmds(specs, providers) do
      {:error, e} ->
        Kit.error(:parse_error, %{
          reason: e,
          spec: specs
        })

      cmds ->
        {:ok, %__MODULE__{spec: Enum.reverse(cmds)}}
    end
  end

  def parse_cmds(specs, providers) do
    specs
    |> Enum.reduce_while([], fn cmd, acc ->
      case Cmd.parse(cmd, providers) do
        {:error, _} = error ->
          {:halt, error}

        {:ok, parsed} ->
          {:cont, [parsed | acc]}
      end
    end)
  end

  def ast(%{spec: items}, index) when is_list(items) do
    {:ok,
     items
     |> Enum.map(fn item ->
       item.__struct__.ast(item, index)
     end)}
  end
end
