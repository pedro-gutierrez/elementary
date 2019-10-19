defmodule Elementary.Settings do
  @moduledoc false

  use Elementary.Provider, rank: :low

  alias Elementary.{Kit, Dict}

  defstruct rank: :low,
            name: nil,
            version: "1",
            spec: Dict.default()

  def parse(
        %{
          "version" => version,
          "name" => name,
          "spec" => spec
        },
        providers
      ) do
    case Dict.parse(spec, providers) do
      {:ok, parsed} ->
        {:ok,
         %__MODULE__{
           name: name,
           version: version,
           spec: parsed
         }}

      {:error, e} ->
        Kit.error(:parse_error, %{
          spec: spec,
          reason: e
        })
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def ast(settings, index) do
    {:module, module_name(settings.name),
     [
       {:fun, :kind, [], :settings},
       {:fun, :name, [], {:symbol, settings.name}},
       {:fun, :get, [], settings.spec.__struct__.ast(settings.spec, index)}
     ]}
  end

  def module_name(name) do
    ["#{name}", "settings"] |> Elementary.Kit.camelize()
  end

  def indexed(mods) do
    {:module, Elementary.Index.Settings,
     (mods
      |> Enum.filter(fn m ->
        m.kind() == :settings
      end)
      |> Enum.flat_map(fn m ->
        [
          {:fun, :get, [{:symbol, m.name()}], {:call, m, :get, []}},
          {:fun, :get, [{:text, m.name()}], {:call, m, :get, []}}
        ]
      end)) ++
       [
         {:fun, :get, [{:var, :_}], {:tuple, [:error, :not_found]}}
       ]}
    |> Elementary.Ast.compiled()
  end
end
