defmodule Elementary.Resolver do
  @moduledoc false

  alias Elementary.Spec
  require Logger

  def resolve(specs) do
    specs
    |> Spec.flatten()
    |> Enum.reduce(specs, fn spec, specs ->
      resolved = resolve(specs, spec)
      Spec.put(specs, resolved)
    end)
  end

  defp resolve(specs, %{"kind" => "app", "spec" => spec0} = spec) do
    Enum.each(spec0["filters"] || [], fn mod ->
      Spec.find!(specs, "app", mod)
    end)

    spec0 = resolve_and_merge(spec0, specs, "settings", "settings")
    %{"modules" => modules} = resolve_and_merge(spec0, specs, "modules", "module")

    spec0 =
      Enum.reduce(["init", "decoders", "encoders", "update"], spec0, fn section, acc ->
        Map.put(acc, section, Map.get(modules, section, %{}))
      end)

    Map.put(spec, "spec", spec0)
  end

  defp resolve(specs, %{"kind" => "port"} = spec) do
    apps = spec["spec"]["apps"] || %{}

    Enum.reduce(apps, [], fn {app, _}, _ ->
      Spec.find!(specs, "app", app)
    end)

    spec
  end

  defp resolve(specs, %{"kind" => "test", "spec" => spec0} = spec) do
    init = spec0["init"] || %{}
    steps = index_steps(spec, %{})

    {init, steps} =
      Enum.reduce(spec0["include"] || [], {init, steps}, fn name, {init, steps} ->
        test_spec = Spec.find!(specs, "test", name)
        init_spec = test_spec["spec"]["init"] || %{}
        {Spec.merge(init, init_spec), index_steps(test_spec, steps)}
      end)

    scenarios =
      Enum.map(spec0["scenarios"] || [], fn scenario ->
        resolved =
          resolve_steps(steps, scenario)
          |> Enum.map(fn step ->
            %{"title" => step["title"], "spec" => Map.drop(step, ["title"])}
          end)

        Map.put(scenario, "steps", resolved)
      end)

    spec0 =
      spec0
      |> Map.put("scenarios", scenarios)
      |> Map.put("init", init)

    Map.put(spec, "spec", spec0)
  end

  defp resolve(_specs, spec), do: spec

  def index_steps(test, index) do
    Enum.reduce((test["spec"] || %{})["steps"] || [], index, fn %{"title" => title} = step,
                                                                index ->
      Map.put(index, title, step)
    end)
  end

  def resolve_steps(steps, %{"title" => parent, "steps" => titles}) do
    Enum.flat_map(titles, fn title ->
      case steps[title] do
        nil ->
          raise "Undefined step \"#{title}\" in \"#{parent}\""

        step ->
          resolve_steps(steps, step)
      end
    end)
  end

  def resolve_steps(_, step), do: [step]

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
