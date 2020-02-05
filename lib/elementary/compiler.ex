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
         def kind(), do: "app"
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
         def kind(), do: "port"
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
         def kind(), do: "settings"

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
    indices = spec["indices"]

    [
      {store_module_name(name),
       quote do
         @name unquote(name)
         @store unquote(registered_name)
         @url unquote(url)
         @pool unquote(pool)
         @indices unquote(Macro.escape(indices))
         @collections unquote(Macro.escape(collections))
         def name(), do: @name
         def kind(), do: "store"

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
           Enum.reduce_while(@collections, :ok, fn %{"name" => col, "indices" => indices}, _ ->
             with :ok <- drop_collection(col),
                  :ok <- create_collection(col),
                  :ok <- ensure_indices(col, indices) do
               {:cont, :ok}
             else
               {:error, e} ->
                 {:halt, mongo_error(e)}
             end
           end)
         end

         def create_collection(col) do
           with {:error, %Mongo.Error{code: 48}} <- Mongo.create(@store, col) do
             :ok
           end
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

         def ensure_indices(col, indices) do
           Enum.reduce_while(indices, :ok, fn index, _ ->
             case @indices[index] do
               nil ->
                 raise "Index \"#{index}\" in #{@name}.#{col} is not defined"

               spec ->
                 opts =
                   case spec do
                     "geo" ->
                       [key: %{index => "2dsphere"}]

                     fields when is_list(fields) ->
                       [unique: true, key: Enum.map(fields, fn f -> {f, 1} end)]
                   end

                 case ensure_index(col, index, opts) do
                   :ok ->
                     {:cont, :ok}

                   other ->
                     {:halt, other}
                 end
             end
           end)
         end

         def ensure_index(col, name, opts) do
           with {:ok, _} <-
                  Mongo.command(
                    @store,
                    [
                      createIndexes: col,
                      indexes: [
                        Keyword.merge(opts, name: name)
                      ]
                    ],
                    []
                  ) do
             :ok
           else
             {:error, %{message: msg}} ->
               {:error, msg}
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

  defp compile(_, %{"kind" => "test", "name" => name, "spec" => spec}) do
    registered_name = String.to_atom("#{name}_test")

    [
      {module_name(name, "test"),
       quote do
         use GenServer
         require Logger
         @name unquote(name)
         @test unquote(registered_name)
         @timeout 1000
         @scenarios unquote(Macro.escape(spec["scenarios"] || []))
         @init unquote(Macro.escape(spec["init"]))

         def name(), do: @name
         def kind(), do: "test"

         def child_spec(opts) do
           %{
             id: @test,
             start: {__MODULE__, :start_link, [opts]},
             type: :worker,
             restart: :temporary,
             shutdown: 5000
           }
         end

         def start_link(opts) do
           GenServer.start_link(__MODULE__, opts, name: @test)
         end

         def init(opts) do
           settings = opts[:settings]
           tag = opts[:tag]
           {:ok, facts} = settings.get()

           {:ok, init} =
             case @init do
               nil ->
                 {:ok, facts}

               init_spec ->
                 Elementary.Encoder.encode(init_spec, facts)
             end

           scenarios = scenarios(tag)

           Process.send_after(self(), :timeout, @timeout)

           {:ok,
            %{
              log: fn _ -> :ok end,
              started: Elementary.Kit.now(),
              settings: settings,
              tag: tag,
              init: init,
              scenarios: scenarios,
              scenario: nil,
              step: nil,
              context: nil,
              report: %{
                total: length(scenarios),
                passed: 0,
                failed: 0
              }
            }, {:continue, :scenario}}
         end

         def handle_continue(:scenario, %{init: init, scenarios: [current | rest]} = state) do
           log =
             case current["debug"] do
               true ->
                 fn msg ->
                   Logger.info(msg)
                 end

               _ ->
                 fn _ -> :ok end
             end

           log.("Starting senario #{current["title"]}")

           {:noreply,
            %{
              state
              | log: log,
                context: init,
                scenario: current,
                scenarios: rest
            }, {:continue, :step}}
         end

         def handle_continue(
               :scenario,
               %{started: started, log: log, report: report, scenarios: []} = state
             ) do
           report =
             Map.merge(
               %{
                 :test => @name,
                 :time => Elementary.Kit.duration(started, :millisecond)
               },
               report
             )

           msg = "Finished: #{inspect(report)}"

           case report.failed do
             0 -> Logger.info(msg)
             _ -> Logger.error(msg)
           end

           {:stop, :normal, state}
         end

         def handle_continue(
               :step,
               %{
                 log: log,
                 report: report,
                 context: context,
                 scenario: %{"title" => title, "steps" => [current | rest]} = scenario
               } = state
             ) do
           log.("Running step \"#{current["title"]}")

           case Elementary.Encoder.encode(current["spec"], context) do
             {:ok, context2} ->
               context = Map.merge(context, context2)
               scenario = Map.put(scenario, "steps", rest)
               log.("Step #{current["title"]} successful")
               log.("Context: #{inspect(context)}")

               {:noreply, %{state | context: context, step: nil, scenario: scenario},
                {:continue, :step}}

             {:error, e} ->
               scenario = Map.put(scenario, "steps", [])
               report = %{report | failed: report.failed + 1}

               Logger.error(
                 "Step \"#{current["title"]}\" in scenario \"#{title}\" failed: #{inspect(e)}"
               )

               {:noreply, %{state | report: report, step: nil, scenario: scenario},
                {:continue, :step}}
           end
         end

         def handle_continue(
               :step,
               %{
                 report: report,
                 log: log,
                 scenario: %{"title" => title, "steps" => []} = scenario
               } = state
             ) do
           log.("Scenario #{title} finished")
           report = %{report | passed: report.passed + 1}
           {:noreply, %{state | report: report}, {:continue, :scenario}}
         end

         def handle_info(:timeout, %{log: log} = state) do
           log.("Test #{@name} timeout")
           {:stop, :normal, state}
         end

         def scenarios(nil) do
           @scenarios
         end

         def scenarios(tag) do
           Enum.filter(@scenarios, fn scenario ->
             Enum.member?(scenario["tags"], tag)
           end)
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
