defmodule Elementary.Compiler do
  @moduledoc false

  use GenServer
  alias Elementary.{Spec, Resolver, Kit, Encoder, Decoder}
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_) do
    {:ok, pid} = Elementary.Kit.watch()
    {:ok, pid}
  end

  def handle_info({:file_event, _, {_, [:created]}}, state) do
    {:noreply, state}
  end

  def handle_info({:file_event, _, {_, _}}, state) do
    compile()
    {:noreply, state}
  end

  def compile() do
    index_specs(Spec.all())
    compile_specs(Spec.all())
  end

  defp compile_specs(specs) do
    specs
    |> Resolver.resolve()
    |> Spec.flatten()
    |> Enum.reduce([], fn spec, mods ->
      mods ++ compile(specs, spec)
    end)
    |> List.flatten()
    |> Enum.map(fn {mod, ast} ->
      {:ok, mod} = defmod(mod, ast)
      mod
    end)
  end

  defp index_specs(specs) do
    mods =
      specs
      |> Spec.flatten()
      |> Enum.map(fn %{"kind" => kind, "name" => name} ->
        {name, kind, module_name(name, kind)}
      end)

    {:ok, _} =
      defmod(
        Elementary.Index,
        Enum.map(mods, fn {name, kind, mod} ->
          quote do
            def get(unquote(kind), unquote(name)) do
              {:ok, unquote(mod)}
            end
          end
        end) ++
          [
            quote do
              def get(kind, name) do
                {:error, :not_found}
              end
            end
          ]
      )
  end

  defp compile(_specs, %{"kind" => "app", "name" => name, "spec" => spec}) do
    init = spec["init"] || %{}
    settings = spec["settings"] || %{}
    encoders = spec["encoders"] || %{}
    decoders = spec["decoders"] || %{}
    update = spec["update"] || %{}

    {:ok, _} = encoded = Encoder.encode(settings, %{}, encoders)
    debug = spec["debug"] == true

    [
      {app_module_name(name),
       quote do
         @name unquote(name)
         @debug unquote(debug)
         @decoders unquote(Macro.escape(decoders))
         @encoders unquote(Macro.escape(encoders))
         @update unquote(Macro.escape(update))
         @init %{"init" => unquote(Macro.escape(init))}

         def name(), do: @name
         def debug(), do: @debug

         def settings() do
           unquote(Macro.escape(encoded))
         end

         def init(settings) do
           with {:ok, model, cmds} <-
                  Encoder.encode(
                    @init,
                    settings
                  ) do
             {:ok, Map.merge(settings, model), cmds}
           end
         end

         def decode(effect, data, context) do
           with specs when is_map(specs) <- @decoders[effect],
                {event, decoded} <-
                  Enum.reduce_while(specs, nil, fn {event, spec}, _ ->
                    case Decoder.decode(spec, data, context) do
                      {:ok, decoded} ->
                        {:halt, {event, decoded}}

                      {:error, _} ->
                        {:cont, nil}
                    end
                  end) do
             {:ok, event, decoded}
           else
             _ ->
               {:error, %{"error" => :decode, "effect" => effect, "data" => data}}
           end
         end

         def update(event, data, model) do
           case @update[event] do
             spec when is_map(spec) ->
               do_update(spec, data, model)

             specs when is_list(specs) ->
               Enum.reduce_while(specs, false, fn spec, _ ->
                 case do_update(spec, data, model) do
                   false ->
                     {:cont, false}

                   {:ok, _, _} = result ->
                     {:halt, result}
                 end
               end)
           end
         end

         defp do_update(%{"model" => model, "cmds" => cmds}, data, _context) do
           with {:ok, encoded} <- Encoder.encode(model, data, @encoders),
                {:ok, cmds} <- Encoder.encode(cmds, data, @encoders) do
             {:ok, encoded, cmds}
           end
         end

         defp do_update(%{"cmds" => cmds}, data, _context) do
           with {:ok, cmds} <- Encoder.encode(cmds, data, @encoders) do
             {:ok, %{}, cmds}
           end
         end

         def encode(encoder, context) do
           Encoder.encode(%{"encoder" => encoder}, context, @encoders)
         end
       end}
    ]
  end

  defp compile(_specs, %{
         "kind" => "port",
         "name" => name,
         "spec" => %{"port" => port, "apps" => apps}
       }) do
    [
      {port_module_name(name),
       quote do
         @name unquote(name)
         @port unquote(port)
         @routes unquote(
                   Enum.flat_map(apps, fn {_, mounts} ->
                     Map.values(mounts)
                   end)
                 )

         def name(), do: @name
         def port(), do: @port
         def routes(), do: @routes

         def start_link() do
           dispatch =
             :cowboy_router.compile([
               {:_,
                unquote(
                  Enum.map(apps, fn {app, %{"http" => route}} ->
                    app_module = Elementary.Compiler.app_module_name(app)
                    {route, Elementary.Http, [app_module]}
                  end)
                  |> Macro.escape()
                )}
             ])

           {:ok, pid} =
             :cowboy.start_clear(
               @name,
               [{:port, @port}],
               %{:env => %{:dispatch => dispatch}}
             )

           IO.inspect(
             port: @name,
             port: @port,
             routes: @routes
           )

           {:ok, pid}
         end

         def child_spec(opts) do
           %{
             id: __MODULE__,
             start: {__MODULE__, :start_link, []},
             type: :worker,
             restart: :permanent,
             shutdown: 500
           }
         end
       end}
    ]
  end

  defp compile(_specs, %{
         "kind" => "settings",
         "name" => name,
         "spec" => spec
       }) do
    {:ok, _} = encoded = Encoder.encode(spec)

    [
      {settings_module_name(name),
       quote do
         @name unquote(name)
         def name(), do: @name

         def get() do
           unquote(Macro.escape(encoded))
         end
       end}
    ]
  end

  defp compile(_specs, %{
         "kind" => "store",
         "name" => name,
         "spec" => spec
       }) do
    registered_name = String.to_atom("#{name}_store")
    pool = spec["pool"] || 1
    url = Elementary.Kit.mongo_url(Map.merge(%{"db" => name}, spec))

    collections = spec["collections"]

    [
      {store_module_name(name),
       quote do
         @name unquote(name)
         @store unquote(registered_name)
         @url unquote(url)
         @pool unquote(pool)
         @collections unquote(collections)
         def name(), do: @name

         def child_spec(opts) do
           %{
             id: @store,
             start:
               {Mongo, :start_link,
                [
                  [
                    name: @store,
                    url: @url,
                    pool_size: @pool
                  ]
                ]},
             type: :worker,
             restart: :permanent,
             shutdown: 5000
           }
         end

         def reset() do
           Enum.reduce_while(@collections, :ok, fn col, _ ->
             case drop_collection(col) do
               :ok ->
                 {:cont, :ok}

               {:error, e} ->
                 {:halt, mongo_error(e)}
             end
           end)
         end

         def drop_collection(col) do
           case Mongo.drop_collection(@store, col) do
             :ok ->
               :ok

             {:error, %{code: 26}} ->
               :ok

             {:error, e} ->
               {:halt, mongo_error(e)}
           end
         end

         def insert(col, doc) when is_map(doc) do
           case Mongo.insert_one(
                  @store,
                  col,
                  doc
                ) do
             {:ok, _} ->
               :ok

             {:error, e} ->
               {:error, mongo_error(e)}
           end
         end

         def find_all(col, query, opts \\ []) do
           {:ok,
            Mongo.find(@store, col, query,
              skip: Keyword.get(opts, :offset, 0),
              limit: Keyword.get(opts, :limit, 20)
            )
            |> Stream.map(&sanitized(&1))
            |> Enum.to_list()}
         end

         def find_one(col, query) do
           case Mongo.find_one(@store, col, query) do
             nil ->
               {:error, :not_found}

             doc ->
               {:ok, sanitized(doc)}
           end
         end

         defp mongo_error(%{write_errors: [error]}) do
           mongo_error(error)
         end

         defp mongo_error(%{"code" => 11000}) do
           :conflict
         end

         defp sanitized(doc) do
           Map.drop(doc, ["_id"])
         end
       end}
    ]
  end

  defp compile(_specs, _), do: []

  defp defmod(mod, content) do
    {:module, mod, _, _} = Module.create(mod, content, Macro.Env.location(__ENV__))
    {:ok, mod}
  end

  def port_module_name(name), do: module_name(name, "port")
  def app_module_name(name), do: module_name(name, "app")
  def settings_module_name(name), do: module_name(name, "settings")
  def store_module_name(name), do: module_name(name, "store")
  defp module_name(name, kind), do: Kit.module_name([name, kind])
end
