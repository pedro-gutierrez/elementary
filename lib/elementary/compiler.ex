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

  def handle_info({:file_event, _, {_, events}}, state) do
    if Enum.member?(events, :modified) do
      compile()
    end

    {:noreply, state}
  end

  def compile() do
    index_specs(Spec.all())
    mods = compile_specs(Spec.all())
    Code.purge_compiler_modules()
    Logger.info("Compiled #{length(mods)} modules")
    mods
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
                {:error, %{"kind" => kind, "name" => name, "error" => "not_found"}}
              end

              def get!(kind, name) do
                case get(kind, name) do
                  {:ok, mod} ->
                    mod

                  {:error, :not_found} ->
                    raise "Kind \"#{kind}\" with name \"#{name}\" is not defined"
                end
              end
            end
          ]
      )
  end

  defp compile(_specs, %{"kind" => "logger" = kind, "name" => name, "spec" => spec}) do
    store = spec["store"]

    {:ok, store} = Elementary.Index.get("store", store)

    [
      {module_name(name, kind),
       quote do
         @name unquote(name)
         @kind unquote(kind)
         @store unquote(store)
         def name(), do: @name
         def kind(), do: @kind

         def store() do
           @store
         end

         def log(%{kind: "app", name: "logs"}), do: :ok
         def log(%{kind: "app", name: "index"}), do: :ok

         def log(data) do
           :ok = unquote(store).insert("log", data, log: :disable)
         end

         def query(q) do
           query =
             q
             |> maybe_timerange_query()
             |> maybe_cast_status_code()

           unquote(store).find_all("log", query, sort: %{"time" => "desc", "$natural" => "desc"})
         end

         defp maybe_timerange_query(%{"from" => from, "to" => to} = q) do
           with {:ok, from, _} <- DateTime.from_iso8601(from),
                {:ok, to, _} <- DateTime.from_iso8601(to) do
             q
             |> Map.drop(["from", "to"])
             |> Map.put("time", %{
               "$gte" => from,
               "$lt" => to
             })
           else
             _ ->
               q
           end
         end

         defp maybe_timerange_query(%{"from" => from} = q) do
           case DateTime.from_iso8601(from) do
             {:ok, from, _} ->
               q
               |> Map.drop(["from"])
               |> Map.put("time", %{
                 "$gte" => from
               })

             _ ->
               q
           end
         end

         defp maybe_timerange_query(q), do: q

         defp maybe_cast_status_code(%{"status" => code} = q) do
           case Integer.parse(code) do
             {code, ""} ->
               Map.put(q, "status", code)

             _ ->
               q
           end
         end

         defp maybe_cast_status_code(q), do: q
       end}
    ]
  end

  defp compile(_specs, %{"kind" => kind, "name" => name, "spec" => spec})
       when kind == "app" or kind == "module" do
    init = spec["init"] || %{}
    settings = spec["settings"] || %{}
    encoders = spec["encoders"] || %{}
    decoders = spec["decoders"] || %{}
    update = spec["update"] || %{}

    filters =
      Enum.map(spec["filters"] || [], fn name ->
        Elementary.Index.get!("app", name)
        module_name(name, "app")
      end)

    {:ok, _} = encoded = Encoder.encode(settings, %{}, encoders)
    debug = spec["debug"] == true

    [
      {module_name(name, kind),
       quote do
         @name unquote(name)
         @kind unquote(kind)
         @debug unquote(debug)
         @filters unquote(filters)
         @decoders unquote(Macro.escape(decoders))
         @encoders unquote(Macro.escape(encoders))
         @update unquote(Macro.escape(update))
         @init %{"init" => unquote(Macro.escape(init))}
         @resolved_spec unquote(Macro.escape(spec))

         def name(), do: @name
         def kind(), do: @kind
         def debug(), do: @debug
         def spec(), do: @resolved_spec

         def settings() do
           unquote(Macro.escape(encoded))
         end

         def filters() do
           @filters
         end

         def encoders(), do: @encoders

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
             nil ->
               {:error, "no_update"}

             spec when is_map(spec) ->
               context = %{"data" => data, "model" => model}
               do_update(spec, context)

             specs when is_list(specs) ->
               context = %{"data" => data, "model" => model}

               Enum.reduce_while(specs, false, fn spec, _ ->
                 case do_update(spec, context) do
                   {:ok, _, _} = result ->
                     {:halt, result}

                   false ->
                     {:cont, false}

                   {:error, _} = err ->
                     {:halt, err}
                 end
               end)
           end
         end

         defp do_update(%{"when" => condition} = spec, context) do
           case Encoder.encode(condition, context, @encoders) do
             {:ok, false} ->
               false

             {:ok, _} ->
               spec
               |> Map.drop(["when"])
               |> do_update(context)

             other ->
               other
           end
         end

         defp do_update(
                %{"model" => model, "cmds" => cmds},
                %{"model" => current_model} = context
              ) do
           with {:ok, encoded} <- Encoder.encode(model, context, @encoders),
                {:ok, cmds} <- Encoder.encode(cmds, Map.merge(current_model, encoded), @encoders) do
             {:ok, encoded, cmds}
           end
         end

         defp do_update(%{"model" => model}, context) do
           with {:ok, encoded} <- Encoder.encode(model, context, @encoders) do
             {:ok, encoded, []}
           end
         end

         defp do_update(
                %{"cmds" => cmds},
                %{"model" => current_model} = context
              ) do
           with {:ok, cmds} <- Encoder.encode(cmds, current_model, @encoders) do
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
         "spec" => %{"port" => port}
       }) do
    {:ok, port} = Encoder.encode(port)
    {port, ""} = Integer.parse(port)

    routes =
      Spec.all()
      |> Spec.all("app")
      |> Enum.flat_map(fn
        {app, %{"spec" => %{"routes" => %{^name => routes}}}} ->
          Enum.map(routes, fn {method, path} ->
            [app: app, path: path, method: method, scheme: :http]
          end)

        _ ->
          []
      end)
      |> Enum.reduce(%{}, fn [app: app, path: path, method: method, scheme: :http], acc ->
        methods = acc[path] || %{}
        Map.put(acc, path, Map.put(methods, method, app))
      end)
      |> Enum.map(fn {path, methods} ->
        %{"path" => path, "apps" => methods}
      end)

    paths = Enum.map(routes, fn %{"path" => path} -> path end)

    [
      {port_module_name(name),
       quote do
         @name unquote(name)
         @port unquote(port)
         @routes unquote(paths)

         def name(), do: @name
         def kind(), do: "port"
         def port(), do: @port
         def routes(), do: @routes

         def start_link() do
           dispatch =
             :cowboy_router.compile([
               {:_,
                unquote(
                  (Enum.map(routes, fn
                     %{"path" => route, "app" => app} ->
                       app_module = Elementary.Compiler.app_module_name(app)
                       {route, Elementary.Http, [app_module]}

                     %{"path" => route, "apps" => apps} ->
                       {route, Elementary.Http,
                        [
                          Enum.reduce(apps, %{}, fn {method, app}, acc ->
                            Map.put(
                              acc,
                              String.upcase(method),
                              Elementary.Compiler.app_module_name(app)
                            )
                          end)
                        ]}
                   end) ++
                     [
                       {"/[...]", :cowboy_static,
                        {:dir, Elementary.Kit.assets(),
                         [
                           {:mimetypes, :cow_mimetypes, :all}
                         ]}}
                     ])
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

    {:ok, url_spec} = Encoder.encode(spec["url"] || %{"db" => name})
    url = Elementary.Kit.mongo_url(url_spec)

    collections = spec["collections"]
    debug = spec["debug"] == true

    [
      {store_module_name(name),
       quote do
         alias Mongo.Session
         require Logger
         @name unquote(name)
         @store unquote(registered_name)
         @url unquote(url)
         @pool unquote(pool)
         @collections unquote(Macro.escape(collections))
         @debug unquote(debug)

         def name(), do: @name
         def kind(), do: "store"
         def debug(), do: @debug

         defp log(data, meta, opts \\ []) do
           if :enable == (opts[:log] || :enable) do
             meta
             |> with_log_payload(data, opts[:data] || :full)
             |> with_log_duration(opts)
             |> with_log_meta()
             |> Elementary.Logger.log()
           end

           data
         end

         defp with_log_payload(meta, {:ok, data}, :summary) when is_list(data) do
           Map.put(meta, :result, %{list: %{size: length(data)}})
         end

         defp with_log_payload(meta, {:ok, data}, _) do
           Map.put(meta, :result, data)
         end

         defp with_log_payload(meta, {:error, reason}, _) do
           Map.put(meta, :result, reason)
         end

         defp with_log_payload(meta, other, _) do
           Map.put(meta, :result, other)
         end

         defp with_log_duration(meta, opts) do
           case opts[:started] do
             nil ->
               meta

             started ->
               Map.put(meta, :duration, Elementary.Kit.millis_since(started))
           end
         end

         defp with_log_meta(meta) do
           Map.merge(meta, %{
             kind: "store",
             name: @name
           })
         end

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

         def empty() do
           Enum.reduce_while(@collections, :ok, fn {col, _}, _ ->
             case empty_collection(col) do
               :ok ->
                 {:cont, :ok}

               {:error, e} ->
                 {:halt, mongo_error(e)}
             end
           end)
         end

         def reset() do
           Enum.reduce_while(@collections, :ok, fn {col, spec}, _ ->
             with :ok <- drop_collection(col),
                  :ok <- create_collection(col, spec),
                  :ok <- ensure_indexes(col, spec["indexes"] || []) do
               {:cont, :ok}
             else
               {:error, e} ->
                 {:halt, mongo_error(e)}
             end
           end)
         end

         def ping() do
           started = Elementary.Kit.millis()

           case Mongo.ping(@store) do
             {:ok, _} ->
               :ok

             {:error, e} ->
               {:error, mongo_error(e)}
           end
           |> log(%{op: :ping}, started: started)
         end

         def empty_collection(col) do
           case Mongo.delete_many(@store, col, %{}) do
             {:ok, _} ->
               :ok

             {:error, e} ->
               {:halt, mongo_error(e)}
           end
           |> log(%{collection: col, op: :empty})
         end

         def create_collection(col, spec) do
           opts = collection_create_opts(spec)

           with {:error, %Mongo.Error{code: 48}} <- Mongo.create(@store, col, opts) do
             :ok
           end
           |> log(%{collection: col, op: :create}, log: :disabled)
         end

         def collection_create_opts(%{"max" => max, "size" => size}) do
           [capped: true, max: max, size: size]
         end

         def collection_create_opts(_), do: []

         def drop_collection(col) do
           case Mongo.drop_collection(@store, col) do
             :ok ->
               :ok

             {:error, %{code: 26}} ->
               :ok

             {:error, e} ->
               {:halt, mongo_error(e)}
           end
           |> log(%{collection: col, op: :drop}, log: :disabled)
         end

         def ensure_indexes(col, indices) do
           Enum.map(indices, fn
             %{"lookup" => field} when is_binary(field) ->
               {"_#{field}_", [unique: false, key: [{field, 1}]]}

             %{"unique" => field} when is_binary(field) ->
               {"_#{field}_", [unique: true, key: [{field, 1}]]}

             %{"unique" => fields} when is_list(fields) ->
               {Enum.join([""] ++ fields ++ [""], "_"),
                [unique: true, key: Enum.map(fields, fn f -> {f, 1} end)]}

             %{"geo" => field} ->
               {"_#{field}_", [key: %{field => "2dsphere"}]}

             %{"expire" => field, "after" => seconds} ->
               {"_#{field}_", [expireAfterSeconds: seconds, key: [{field, 1}]]}
           end)
           |> Enum.each(fn {name, opts} = spec ->
             case ensure_index(col, name, opts) do
               :ok ->
                 :ok

               other ->
                 raise "Error creating index #{inspect(spec)} on collection #{col}: #{
                         inspect(other)
                       }"
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
           |> log(%{collection: col, op: :ensure_index, index: name}, log: :disabled)
         end

         def insert(col, doc, opts \\ []) when is_map(doc) do
           started = Elementary.Kit.millis()
           doc = Elementary.Kit.with_mongo_id(doc)

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
           |> log(%{collection: col, op: :insert, doc: doc}, Keyword.put(opts, :started, started))
         end

         def update(col, where, doc, upsert \\ false) when is_map(doc) do
           started = Elementary.Kit.millis()
           where = Elementary.Kit.with_mongo_id(where)

           doc =
             Elementary.Kit.with_mongo_id(doc)
             |> case do
               %{"$push" => _} = doc -> doc
               %{"$pull" => _} = doc -> doc
               doc -> %{"$set" => doc}
             end

           case Mongo.update_one(
                  @store,
                  col,
                  where,
                  doc,
                  upsert: upsert
                ) do
             {:ok,
              %Mongo.UpdateResult{
                acknowledged: true,
                modified_count: modified,
                upserted_ids: upserted_ids
              }} ->
               {:ok, modified + length(upserted_ids)}

             {:error, e} ->
               {:error, mongo_error(e)}
           end
           |> log(%{collection: col, op: :update, where: where, doc: doc, upsert: upsert},
             started: started
           )
         end

         def delete(col, doc) when is_map(doc) do
           started = Elementary.Kit.millis()
           doc = Elementary.Kit.with_mongo_id(doc)

           case Mongo.delete_one(
                  @store,
                  col,
                  doc
                ) do
             {:ok, %Mongo.DeleteResult{acknowledged: true, deleted_count: deleted}} ->
               {:ok, deleted}

             {:error, e} ->
               {:error, mongo_error(e)}
           end
           |> log(%{collection: col, op: :delete, where: doc}, started: started)
         end

         def find_all(col, query, opts \\ []) do
           started = Elementary.Kit.millis()

           opts =
             case opts[:sort] do
               nil ->
                 []

               sort ->
                 [
                   sort:
                     Enum.map(sort, fn
                       {k, "asc"} ->
                         {k, 1}

                       {k, "desc"} ->
                         {k, -1}
                     end)
                 ]
             end

           opts =
             Keyword.merge(opts,
               skip: Keyword.get(opts, :offset, 0),
               limit: Keyword.get(opts, :limit, 20)
             )

           query = Elementary.Kit.with_mongo_id(query)

           {:ok,
            Mongo.find(@store, col, query, opts)
            |> Stream.map(&Elementary.Kit.without_mongo_id(&1))
            |> Enum.to_list()}
           |> log(%{collection: col, op: :find, where: query, options: opts},
             started: started,
             data: :summary
           )
         end

         def find_one(col, query, opts \\ []) do
           started = Elementary.Kit.millis()
           query = Elementary.Kit.with_mongo_id(query)

           {res, op} =
             case opts[:delete] do
               true ->
                 {Mongo.find_one_and_delete(@store, col, query), :find_one_and_delete}

               _ ->
                 {Mongo.find_one(@store, col, query), :find_one}
             end

           case res do
             nil ->
               {:error, :not_found}

             doc ->
               {:ok, Elementary.Kit.without_mongo_id(doc)}
           end
           |> log(%{collection: col, op: op, where: query}, started: started)
         end

         def aggregate(col, p, opts \\ []) do
           started = Elementary.Kit.millis()
           p = pipeline(p)

           {:ok,
            Mongo.aggregate(@store, col, p, opts)
            |> Stream.map(&Elementary.Kit.without_mongo_id(&1))
            |> Enum.to_list()}
           |> log(%{collection: col, op: :aggregate, pipeline: p, options: opts},
             started: started,
             data: :summary
           )
         end

         defp mongo_error(%{write_errors: [error]}) do
           mongo_error(error)
         end

         defp mongo_error(%{"code" => 11000}) do
           :conflict
         end

         defp pipeline(items) do
           Enum.map(items, &pipeline_item(&1))
         end

         defp pipeline_item(%{"$match" => query}) do
           %{"$match" => Elementary.Kit.with_mongo_id(query)}
         end

         defp pipeline_item(%{
                "$lookup" => %{
                  "from" => foreignCol,
                  "localField" => localField,
                  "foreignField" => foreignField,
                  "as" => as
                }
              }) do
           %{
             "$lookup" => %{
               "from" => foreignCol,
               "localField" => intern_field(localField),
               "foreignField" => intern_field(foreignField),
               "as" => as
             }
           }
         end

         defp pipeline_item(%{
                "$lookup" => %{
                  "from" => foreignCol,
                  "as" => as
                }
              }) do
           %{
             "$lookup" => %{
               "from" => foreignCol,
               "localField" => intern_field(as),
               "foreignField" => "_id",
               "as" => as
             }
           }
         end

         defp pipeline_item(other), do: other

         defp intern_field("id"), do: "_id"
         defp intern_field(other), do: other
       end}
    ]
  end

  defp compile(_, %{"kind" => "test", "name" => name, "spec" => spec}) do
    registered_name = String.to_atom("#{name}_test")
    debug = spec["debug"] == true

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
         @debug unquote(debug)

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
                 {:ok, encoded} = Elementary.Encoder.encode(init_spec, facts)
                 {:ok, Map.merge(facts, encoded)}
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
              scenario_started: nil,
              step: nil,
              context: nil,
              trace: %{
                scenarios: [],
                scenario: nil
              },
              report: %{
                total: length(scenarios),
                passed: 0,
                failed: 0,
                failures: []
              }
            }, {:continue, :scenario}}
         end

         def handle_continue(
               :scenario,
               %{init: init, trace: trace, scenarios: [current | rest]} = state
             ) do
           log = debug_fun(current, @debug)
           title = current["title"]
           log.(title)

           {:noreply,
            %{
              state
              | log: log,
                context: init,
                scenario: current,
                scenario_started: Elementary.Kit.now(),
                scenarios: rest,
                trace: trace_with_new_scenario(trace)
            }, {:continue, :step}}
         end

         def handle_continue(
               :scenario,
               %{started: started, log: log, trace: trace, report: report, scenarios: []} = state
             ) do
           report =
             Map.merge(
               %{
                 :test => @name,
                 :time => Elementary.Kit.duration(started, :millisecond)
               },
               report
             )

           msg = "#{inspect(report, pretty: true)}"

           case report.failed do
             0 -> Logger.info(msg)
             _ -> Logger.error(msg)
           end

           write_trace(trace, state)

           {:stop, :normal, state}
         end

         def handle_continue(
               :step,
               %{
                 log: log,
                 report: report,
                 context: context,
                 trace: trace,
                 scenario_started: scenario_started,
                 scenario: %{"title" => scenario_title, "steps" => [current | rest]} = scenario
               } = state
             ) do
           step_title = current["title"]
           step_spec = current["spec"]
           scenario_id = id(scenario_title)
           step_id = id(step_title, scenario_title)
           started = Elementary.Kit.now()

           case Elementary.Encoder.encode(step_spec, context) do
             {:ok, output} ->
               elapsed = Elementary.Kit.duration(started, :millisecond)

               new_context =
                 case is_map(output) do
                   true -> Map.merge(context, output)
                   false -> context
                 end

               scenario = Map.put(scenario, "steps", rest)
               log.("#{step_title} (#{elapsed}ms)")
               log.("    #{inspect(output)}")

               step_trace = %{
                 title: step_title,
                 id: step_id,
                 scenario: scenario_id,
                 status: :success,
                 time: elapsed,
                 spec: step_spec,
                 context: context,
                 output: output
               }

               {:noreply,
                %{
                  state
                  | trace: trace_with_step(trace, step_trace),
                    context: new_context,
                    step: nil,
                    scenario: scenario
                }, {:continue, :step}}

             {:error, e} ->
               elapsed = Elementary.Kit.duration(started, :millisecond)
               scenario_elapsed = Elementary.Kit.duration(scenario_started, :millisecond)
               scenario = Map.put(scenario, "steps", [])
               failures = report.failures

               report = %{
                 report
                 | failures: [scenario_title | failures],
                   failed: report.failed + 1
               }

               step_trace = %{
                 title: step_title,
                 id: step_id,
                 scenario: scenario_id,
                 status: :error,
                 time: elapsed,
                 spec: step_spec,
                 context: context,
                 output: e
               }

               scenario_trace = %{
                 title: scenario_title,
                 status: :error,
                 time: scenario_elapsed
               }

               Logger.error(
                 "#{
                   inspect(
                     step_trace,
                     pretty: true
                   )
                 }"
               )

               trace =
                 trace
                 |> trace_with_step(step_trace)
                 |> trace_with_scenario(scenario_trace)

               {:noreply,
                %{
                  state
                  | trace: trace,
                    report: report,
                    step: nil,
                    scenario: scenario
                }, {:continue, :scenario}}
           end
         end

         def handle_continue(
               :step,
               %{
                 report: report,
                 trace: trace,
                 log: log,
                 scenario_started: started,
                 scenario: %{"title" => title, "steps" => []} = scenario
               } = state
             ) do
           elapsed = Elementary.Kit.duration(started, :millisecond)
           Logger.info("Scenario \"#{title}\" (#{elapsed}ms)")
           report = %{report | passed: report.passed + 1}

           scenario_trace = %{
             title: title,
             status: :success,
             time: elapsed,
             id: id(title),
             tags: scenario["tags"] || []
           }

           {:noreply,
            %{state | trace: trace_with_scenario(trace, scenario_trace), report: report},
            {:continue, :scenario}}
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
             Enum.member?(scenario["tags"] || [], tag)
           end)
         end

         defp debug_fun(_, true) do
           fn msg ->
             Logger.info(msg)
           end
         end

         defp debug_fun(spec, _) do
           case Enum.member?(spec["tags"] || [], "debug") do
             true ->
               debug_fun(spec, true)

             _ ->
               fn _ -> :ok end
           end
         end

         defp trace_with_new_scenario(trace) do
           %{trace | scenario: %{steps: []}}
         end

         defp trace_with_scenario(
                %{scenarios: scenarios, scenario: %{steps: steps}} = trace,
                scenario_trace
              ) do
           scenario_trace =
             scenario_trace
             |> Map.put(:steps, Enum.reverse(steps))

           %{
             trace
             | scenarios: [scenario_trace | scenarios],
               scenario: nil
           }
         end

         defp trace_with_step(
                %{scenario: %{steps: steps} = scenario} = trace,
                step_trace
              ) do
           %{trace | scenario: %{scenario | steps: [step_trace | steps]}}
         end

         defp write_trace(%{scenarios: scenarios} = trace, _) do
           path = "#{Elementary.Kit.assets()}/tests.json"
           scenarios = Enum.reverse(scenarios)
           File.write!(path, Jason.encode!(scenarios))
           Logger.info("Written #{path}")
         end

         defp id(title) do
           "#{:erlang.phash2(title)}"
         end

         defp id(title, parent) do
           id(parent <> title)
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
