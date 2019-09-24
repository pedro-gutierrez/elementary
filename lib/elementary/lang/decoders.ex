defmodule Elementary.Lang.Decoders do
  @moduledoc false

  use Elementary.Provider,
    module: __MODULE__

  alias Elementary.Kit
  alias Elementary.Lang.Clause

  defstruct spec: %{}

  def parse(%{"decoders" => spec}, providers) when is_map(spec) do
    case parse_decoders(spec, providers) do
      {:error, e} ->
        Kit.error(:parse_error, e)

      {:ok, decoders} ->
        {:ok, %__MODULE__{spec: decoders}}
    end
  end

  def parse(decs, _) do
    {:ok, %__MODULE__{}}
  end

  defp parse_decoders(decoders, providers) do
    decoders
    |> Enum.reduce_while(%{}, fn {interface, decs2}, by_interface ->
      decs2
      |> Enum.reduce_while(%{}, fn {name, spec}, by_name ->
        case spec |> Kit.parse_spec(providers) do
          {:ok, parsed} ->
            {:cont, Map.put(by_name, name, parsed)}

          {:error, _} = e ->
            {:halt, e}
        end
      end)
      |> case do
        {:error, _} = e ->
          {:halt, e}

        by_name ->
          {:cont, Map.put(by_interface, interface, by_name)}
      end
    end)
    |> case do
      {:error, _} = e ->
        e

      parsed ->
        {:ok, parsed}
    end
  end

  def ast(%{spec: interfaces}, _index) do
    (interfaces
     |> Enum.flat_map(fn {i, names} ->
       names
       |> Enum.map(fn {name, spec} ->
         spec.__struct__.decoder_ast(spec, 0)
         |> decoder_fun_ast(i, name)
       end)
     end)) ++
      [
        not_implemented_ast()
      ]
  end

  def not_implemented_ast() do
    {:fun, :decode, [:_, :_, :_], {:error, :no_decoder}}
  end

  defp decoder_fun_ast({pattern, guards, data, _}, i, name) do
    {:fun, :decode, [{:text, i}, pattern, :_context], guards,
     {:tuple, [:ok, {:text, name}, data]}}
  end
end
