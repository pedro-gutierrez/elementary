defmodule Elementary.Lang.Settings do
  @moduledoc false

  use Elementary.Provider, rank: :low

  alias Elementary.{Kit}
  alias Elementary.Lang.{Dict}

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
       {:fun, :get, [], settings.spec.__struct__.ast(settings.spec, index)}
     ]}
  end

  def module_name(name) do
    ["#{name}", "settings"] |> Elementary.Kit.camelize()
  end
end
