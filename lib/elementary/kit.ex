defmodule Elementary.Kit do
  @moduledoc false

  @doc """
  Returns the home folrder, where all yamls are
  """
  def home(), do: System.get_env("ELEMENTARY_HOME", "/elementary")

  @doc """
  Discovers all yaml filenames in the home folder
  """
  def yamls() do
    Path.wildcard(home() <> "/**/*.yml")
  end

  @doc """
  Parse the given filename as yaml
  """
  def read_yaml(path) do
    YamlElixir.read_from_file(path)
  end

  @doc """
  Parse all yamls in the home folder
  """
  def read_yamls() do
    yamls()
    |> Enum.map(fn yaml ->
      {:ok, content} = read_yaml(yaml)
      content = Map.put(content, "source", yaml)
      Map.put_new(content, "version", "1")
    end)
  end

  @doc """
  Start watching the home folder for file changes
  """
  def watch() do
    {:ok, pid} = FileSystem.start_link(dirs: [home()])
    FileSystem.subscribe(pid)
    {:ok, pid}
  end

  def plugins() do
    Application.get_env(:elementary, :provider_apps, [:elementary])
    |> Enum.flat_map(&mods(&1))
  end

  def mods(app) do
    app_dir = Application.app_dir(app)

    Path.wildcard(app_dir <> "/ebin/*.beam")
    |> Enum.map(fn path ->
      mod_name = Path.rootname(Path.basename(path))
      mod = mod_name |> String.to_atom()
      beam_file = String.to_charlist(app_dir <> "/ebin/" <> mod_name)
      :code.purge(mod)
      :code.load_abs(beam_file)
      mod
    end)
  end

  defp of_kind(mods, kind) do
    Enum.filter(mods, fn mod ->
      kind in (mod.module_info(:attributes)[:behaviour] || [])
    end)
  end

  @doc """
  Discovers all modules in the given apps, that implement
  the Elementary.Provider behavior. Providers are used to parse
  yaml specs and to compile them into Elixir code
  """
  def providers(plugins) do
    plugins
    |> of_kind(Elementary.Provider)
    |> sorted_providers()
    |> Enum.reverse()
  end

  def effects(plugins) do
    plugins
    |> of_kind(Elementary.Effect)
  end

  def inspect_and_return(term) do
    IO.inspect(term)
    term
  end

  defp sorted_providers(providers) do
    Enum.sort(providers, fn p1, p2 ->
      precedes(p1.rank(), p2.rank())
    end)
  end

  @doc """
  Parse the given yaml, using the given providers. Since
  we do not have any information about the kind, this function
  will iterate all providers until there is one that returns a
  valid parsed spec
  """
  def parse_spec(yaml, providers) do
    parse_spec_using_providers(providers, yaml, providers)
  end

  @doc """
  Parse the given spec, using the given list of providers.
  We try all providers, one by one, until one of them succesfully
  parses the yaml syntax. If no provider is able to
  parse, not event the default ones, then we return an error
  """
  def parse_spec_using_providers([], yaml) do
    error(:no_parser, yaml)
  end

  def parse_spec_using_providers([p | rest], yaml, providers) do
    case yaml |> p.parse(providers) do
      {:error, %{reason: :not_supported}} ->
        parse_spec_using_providers(rest, yaml, providers)

      {:error, _} = e ->
        e

      {:ok, _} = r ->
        r
    end
  end

  def error(reason, data) do
    {:error, %{reason: reason, data: data}}
  end

  def parse_specs([] = yamls, _) do
    error(:no_yamls, yamls)
  end

  def parse_specs(yamls, providers) do
    case Enum.reduce_while(yamls, [], fn yaml, specs ->
           case yaml |> parse_spec(providers) do
             {:ok, spec} ->
               {:cont, [spec | specs]}

             {:error, _} = e ->
               {:halt, e}
           end
         end) do
      {:error, _} = e ->
        e

      specs ->
        {:ok, specs}
    end
  end

  def sorted_specs(specs) do
    specs
    |> Enum.sort(fn s1, s2 ->
      precedes(s1, s2)
    end)
  end

  def precedes(%{rank: r1}, %{rank: r2}) do
    precedes(r1, r2)
  end

  def precedes(:lowest, _), do: true
  def precedes(_, :lowest), do: false
  def precedes(:low, _), do: true
  def precedes(:medium, :high), do: true
  def precedes(_, _), do: false

  @doc """
  Compile the given spec using the given providers. All providers
  supporting the given spec will be given a chance to produce
  modules
  """
  def compile_specs(specs, providers) do
    Code.compiler_options(ignore_module_conflict: true)

    case specs
         |> Enum.reduce_while([], fn spec, mods ->
           case spec |> compile_spec(specs, providers) do
             {:error, _} = e ->
               {:halt, e}

             {:ok, more_mods} ->
               {:cont, more_mods ++ mods}
           end
         end) do
      {:error, _} = e ->
        e

      mods ->
        {:ok, mods}
    end
  end

  def compile_spec(spec, specs, providers) do
    providers
    |> Enum.filter(fn p ->
      spec.__struct__ == p.module()
    end)
    |> compile_spec_with_providers(spec, specs)
  end

  def compile_spec_with_providers([], spec, _) do
    error(:no_compilers, spec)
  end

  def compile_spec_with_providers(providers, spec, specs) do
    case providers
         |> Enum.reduce_while([], fn p, mods ->
           case spec |> p.compile(specs) |> compile_modules() do
             {:error, _} = e ->
               {:halt, e}

             {:ok, more_mods} ->
               {:cont, more_mods ++ mods}
           end
         end) do
      {:error, _} = e ->
        e

      mods ->
        Code.purge_compiler_modules()

        {:ok, mods}
    end
  end

  def compile_modules(sources) do
    case sources
         |> Enum.reduce_while([], fn src, mods ->
           case src |> Code.compile_string() do
             [{mod, _}] ->
               {:cont, [mod | mods]}

             other ->
               {:halt, error(:compile_error, %{source: src, reason: other})}
           end
         end) do
      {:error, _} = e ->
        e

      mods ->
        {:ok, mods}
    end
  end

  def asts(specs) do
    specs
    |> sorted_specs()
    |> Enum.reduce_while([], fn spec, asts ->
      more_asts =
        spec
        |> asts(asts)

      {:cont, asts ++ more_asts}
    end)
  end

  defp asts(spec, index) do
    case spec.__struct__.ast(spec, index) do
      asts when is_list(asts) ->
        asts

      {:module, _, _} = single ->
        [single]
    end
  end

  @doc """
  Defines whether or not the given module can be added to a supervision
  tree (Eg. ports)
  """
  def defines_child_spec?(mod) do
    Kernel.function_exported?(mod, :child_spec, 1)
  end

  def supervised(mods) do
    mods
    |> Enum.filter(fn mod ->
      Kernel.function_exported?(mod, :supervised, 0) &&
        mod.supervised()
    end)
  end

  @doc """
  Simple structured logging. For the moment we are inspecting into the console
  but we should send to a central repo for consolidated logs
  """
  def log(kind, name, data) do
    IO.inspect(%{
      kind: kind,
      name: name,
      data: data,
      time: DateTime.utc_now(),
      node: Node.self()
    })
  end

  def camelize(parts) do
    parts
    |> Enum.map(&String.capitalize(&1))
    |> Enum.join("")
  end

  @doc """
  Generates a new variable name, for the given number
  and returns the next variable number to use. This is especially
  useful when building decoder asts, so that we can bind patterns
  to variables
  """
  def new_var(lv) do
    {"v#{lv}" |> String.to_atom(), lv + 1}
  end
end
