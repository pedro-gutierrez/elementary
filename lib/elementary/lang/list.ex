defmodule Elementary.Lang.List do
  @moduledoc false

  use Elementary.Provider,
    kind: "list",
    module: __MODULE__

  alias Elementary.Kit

  defstruct spec: []

  def parse(specs, providers) when is_list(specs) do
    case Enum.reduce_while(specs, [], fn spec, acc ->
           case Kit.parse_spec(spec, providers) do
             {:ok, parsed} ->
               {:cont, [parsed | acc]}

             {:error, _} = e ->
               {:halt, e}
           end
         end) do
      {:error, e} ->
        Kit.error(:parse_error, e)

      items ->
        {:ok, %__MODULE__{spec: items |> Enum.reverse()}}
    end
  end

  def parse(%{"list" => "empty"}, providers) do
    {:ok, %__MODULE__{spec: :empty}}
  end

  def parse(%{"list" => spec}, providers) do
    parse(spec, providers)
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def ast(%{spec: items}, index) when is_list(items) do
    {:list,
     items
     |> Enum.map(fn i ->
       i.__struct__.ast(i, index)
     end)}
  end

  def ast(%{spec: :empty}, _) do
    {:list, :empty}
  end

  def decoder_ast(%{spec: :empty}, _) do
    {{:list, []}, [], []}
  end
end
