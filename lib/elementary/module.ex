defmodule Elementary.Module do
  @moduledoc false

  use Elementary.Provider

  alias Elementary.Kit
  alias Elementary.{Init, Decoders, Update, Encoders}

  defstruct rank: :medium,
            kind: :module,
            name: "",
            version: "1",
            spec: %{
              init: %{},
              decoders: %{},
              encoders: %{},
              update: %{}
            }

  def parse(
        %{
          "kind" => "module",
          "version" => version,
          "name" => name,
          "spec" => raw_spec
        },
        providers
      ) do
    with spec <- %__MODULE__{name: name, version: version},
         {:ok, spec} <- parse_spec(spec, raw_spec, providers) do
      {:ok, spec}
    else
      {:error, e} ->
        Kit.error(:parse_error, %{
          kind: :module,
          name: name,
          reason: e
        })
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def parse_spec(spec, raw_spec, providers) do
    with {:ok, spec} <- with_section(spec, raw_spec, providers, :init, Init),
         {:ok, spec} <- with_section(spec, raw_spec, providers, :decoders, Decoders),
         {:ok, spec} <- with_section(spec, raw_spec, providers, :update, Update),
         {:ok, spec} <- with_section(spec, raw_spec, providers, :encoders, Encoders) do
      {:ok, spec}
    end
  end

  defp with_section(%{spec: spec} = mod, raw, providers, section, parser) do
    case raw |> parser.parse(providers) do
      {:ok, parsed} ->
        {:ok, %{mod | spec: Map.put(spec, section, parsed)}}

      {:error, %{reason: :not_supported}} ->
        {:ok, %{mod | spec: Map.put(spec, section, parser.default())}}

      {:error, e} ->
        Kit.error(:parse_error, %{
          section: section,
          reason: e
        })
    end
  end

  def ast(mod, index) do
    ast(mod, mod.name |> module_name(), mod.name, index)
  end

  def ast(mod, mod_name, name, index) do
    {:module, mod_name,
     [
       {:fun, :kind, [], mod.kind},
       {:fun, :name, [], {:symbol, name}}
     ] ++
       Init.ast(mod.spec.init, index) ++
       Update.ast(mod.spec.update, index) ++
       Decoders.ast(mod.spec.decoders, index) ++
       Encoders.ast(mod.spec.encoders, index)}
  end

  def module_name(name) do
    Module.concat([
      Elementary.Kit.camelize([
        "#{name}",
        "module"
      ])
    ])
  end
end
