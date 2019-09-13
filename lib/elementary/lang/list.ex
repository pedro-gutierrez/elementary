defmodule Elementary.Lang.List do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit

  defstruct items: []

  def parse(specs, providers) when is_list(specs) do
    case Enum.reduce(specs, [], fn spec, acc ->
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
        {:ok, %__MODULE__{items: items |> Enum.reverse()}}
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)
end
