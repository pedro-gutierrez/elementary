defmodule Elementary.Resolver do
  @moduledoc false

  alias Elementary.Spec

  def resolve(specs) do
    specs
    |> Spec.flatten()
    |> Enum.reduce(specs, fn spec, specs ->
      resolved = resolve(specs, spec)
      Spec.put(specs, resolved)
    end)
  end

  defp resolve(specs, %{"kind" => "app", "spec" => spec0} = spec) do
    spec0 = resolve_and_merge(spec0, specs, "settings", "settings")
    %{"modules" => modules} = resolve_and_merge(spec0, specs, "modules", "module")

    spec0 =
      Enum.reduce(["init", "decoders", "encoders", "update"], spec0, fn section, acc ->
        Map.put(acc, section, Map.get(modules, section, %{}))
      end)

    Map.put(spec, "spec", spec0)
  end

  defp resolve(_specs, spec), do: spec

  def resolve_and_merge(spec, specs, prop, kind) do
    names = Map.get(spec, prop, [])
    merged = merge(names, kind, specs)
    Map.put(spec, prop, merged)
  end

  def merge(names, kind, specs) do
    Enum.map(names, fn name ->
      Spec.find!(specs, kind, name)
    end)
    |> Enum.map(fn %{"spec" => spec} ->
      spec
    end)
    |> Spec.merge()
  end
end
