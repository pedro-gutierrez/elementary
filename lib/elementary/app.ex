defmodule Elementary.App do
  @moduledoc false

  use Elementary.Provider
  alias(Elementary.{Ast, Kit, Decoders, Encoders, Update, Settings})

  defstruct rank: :high,
            name: nil,
            version: "1",
            settings: [],
            modules: [],
            entities: []

  def parse(
        %{
          "version" => version,
          "kind" => "app",
          "name" => name,
          "spec" => spec
        },
        _
      ) do
    with {:ok, modules} <- parse_modules(spec),
         {:ok, entities} <- parse_entities(spec),
         {:ok, settings} <- parse_settings(spec) do
      {:ok,
       %__MODULE__{
         name: String.to_atom(name),
         version: version,
         settings: Kit.unique_atoms([name | settings]),
         modules: Kit.unique_atoms(modules),
         entities: Kit.unique_atoms(entities)
       }}
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  defp parse_modules(spec) do
    {:ok, Map.get(spec, "modules", [])}
  end

  defp parse_entities(spec) do
    {:ok, Map.get(spec, "entities", [])}
  end

  defp parse_settings(spec) do
    {:ok, Map.get(spec, "settings", [])}
  end

  def ast(app, asts) do
    mod_names = app.modules |> Enum.map(&Elementary.Module.module_name(&1))
    mod_asts = asts |> Ast.filter({:module, mod_names})
    settings_names = Enum.map(app.settings, &Settings.module_name(&1))
    settings_asts = Ast.filter(asts, {:module, settings_names})

    [
      {:module, app_name(app.name),
       [
         {:fun, :kind, [], :app},
         {:fun, :name, [], app.name},
         {:fun, :entities, [], app.entities},
         {:fun, :modules, [], app.modules},
         settings_ast(settings_asts),
         init_ast(mod_asts)
       ] ++
         update_ast(mod_asts) ++
         decoder_ast(mod_asts) ++
         encoder_ast(mod_asts)}
    ]
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

  def app_name(name) do
    Module.concat([
      Kit.camelize([name, "App"])
    ])
  end

  def indexed(mods) do
    Ast.index(mods, Elementary.Index.App, :app)
    |> Ast.compiled()
  end

  defmacro __using__(_opts) do
    quote do
      require Logger

      defp error(context, e) do
        Logger.error("#{inspect(Keyword.merge(context, error: e))}")
        {:error, e}
      end

      defp decode(mod, effect, data, model) do
        case mod.decode(effect, data, model) do
          {:ok, event, decoded} ->
            update(mod, event, decoded, model)

          {:error, e} ->
            error([app: mod, effect: effect], e)
        end
      end

      defp update(mod, event, data, model0) do
        case mod.update(event, data, model0) do
          {:ok, model, [{effect, enc}]} ->
            cmd(mod, effect, enc, Map.merge(model0, model))

          {:ok, model, [effect]} ->
            cmd(mod, effect, nil, Map.merge(model0, model))

          {:ok, model, []} ->
            {:ok, model}
        end
      end

      defp cmd(mod, :return, nil, model) do
        {:ok, %{"status" => "ok"}}
      end

      defp cmd(mod, effect, nil, model) do
        effect(mod, effect, nil, model)
      end

      defp cmd(mod, effect, enc, model) do
        case mod.encode(enc, model) do
          {:ok, encoded} ->
            case effect do
              :return ->
                {:ok, encoded}

              _ ->
                effect(mod, effect, encoded, model)
            end

          {:error, e} ->
            error([app: mod, encoder: enc], e)
        end
      end

      defp effect(mod, effect, encoded, model) do
        with {:ok, effect_mod} <- Elementary.Index.Effect.get(effect),
             {:ok, data} <- effect_mod.call(encoded) do
          decode(mod, effect, data, model)
        else
          {:error, e} ->
            error([app: mod, effect: effect, data: encoded], e)
            {:error, :internal_error}

          other ->
            error([app: mod, effect: effect, data: encoded], %{unexpected: other})
        end
      end
    end
  end
end
