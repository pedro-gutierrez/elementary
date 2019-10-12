defmodule Elementary.Lang.App do
  @moduledoc false

  use Elementary.Provider,
    kind: "app",
    module: __MODULE__

  alias Elementary.{Ast, Kit}
  alias Elementary.Lang.{Module, Update, Decoders, Encoders, Settings}

  defstruct rank: :high,
            name: "",
            version: "1",
            settings: [],
            modules: []

  def parse(
        %{
          "version" => version,
          "kind" => "app",
          "name" => name,
          "spec" =>
            %{
              "modules" => modules
            } = spec
        },
        _
      ) do
    settings =
      case spec do
        %{"settings" => settings} ->
          [name | settings]

        _ ->
          [name]
      end

    {:ok,
     %__MODULE__{
       name: name,
       version: version,
       settings: Enum.uniq(settings),
       modules: Enum.uniq(modules)
     }}
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def ast(app, asts) do
    mod_names = app.modules |> Enum.map(&Module.module_name(&1))
    mod_asts = asts |> Ast.filter({:module, mod_names})

    settings_names = Enum.map(app.settings, &Settings.module_name(&1))
    settings_asts = Ast.filter(asts, {:module, settings_names})

    callback = [app.name, "app"] |> Elementary.Kit.camelize()

    asts = [
      {:module, callback,
       [
         {:fun, :name, [], {:symbol, app.name}},
         {:fun, :modules, [],
          app.modules
          |> Enum.map(fn m ->
            {:symbol, m}
          end)},
         mod_asts |> init_ast(),
         settings_asts |> settings_ast()
       ] ++
         (mod_asts |> update_ast()) ++
         (mod_asts |> decoder_ast()) ++
         (mod_asts |> encoder_ast())},
      {:module, [app.name, "state", "machine"] |> Elementary.Kit.camelize(),
       [
         {:usage, Elementary.StateMachine,
          [
            name: app.name,
            callback: callback_module_atom(app)
          ]}
       ]}
    ]

    asts
  end

  defp callback_module_atom(app) do
    [
      "elixir.",
      app.name,
      "app"
    ]
    |> Kit.camelize()
    |> String.to_atom()
  end

  defp settings_ast(mods) do
    asts =
      mods
      |> Enum.flat_map(fn ast ->
        ast
        |> Ast.filter({:fun, :get})
      end)
      |> Enum.map(fn {:fun, :get, [], expr} ->
        expr
      end)
      |> Ast.aggregated()
      |> case do
        nil ->
          {:dict, []}

        asts ->
          asts
      end

    {:fun, :settings, [], asts}
  end

  defp init_ast(mods) do
    ast =
      mods
      |> Enum.flat_map(fn ast ->
        ast
        |> Ast.filter({:fun, :init})
      end)
      |> Enum.map(fn {:fun, :init, [_], expr} ->
        expr
      end)
      |> Ast.aggregated()

    data_var = Elementary.Ast.fn_clause_var_name(ast, :data)
    {:fun, :init, [data_var], ast}
  end

  defp update_ast(mods) do
    (mods
     |> Enum.flat_map(fn ast ->
       ast
       |> Ast.filter({:fun, :update})
       |> Enum.drop(-1)
     end)) ++
      [
        Update.not_implemented_ast()
      ]
  end

  defp decoder_ast(mods) do
    (mods
     |> Enum.flat_map(fn ast ->
       ast
       |> Ast.filter({:fun, :decode})
       |> Enum.drop(-1)
     end)) ++
      [
        Decoders.not_implemented_ast()
      ]
  end

  defp encoder_ast(mods) do
    (mods
     |> Enum.flat_map(fn ast ->
       ast
       |> Ast.filter({:fun, :encode})
       |> Enum.drop(-1)
     end)) ++
      [
        Encoders.not_implemented_ast()
      ]
  end
end
