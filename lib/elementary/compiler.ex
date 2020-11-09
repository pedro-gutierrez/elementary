defmodule Elementary.Compiler do
  @moduledoc false

  use GenServer
  alias Elementary.{Index, Spec, Resolver}
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_) do
    {:ok, pid} = Elementary.Kit.watch()
    compile()
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
    owner = self()

    spawn(fn ->
      specs =
        Spec.all()
        |> Resolver.resolve()
        |> Spec.flatten()

      Enum.each(specs, fn spec ->
        Index.put(spec)
      end)

      ["cluster", "settings", "port", "store"]
      |> Enum.each(fn kind ->
        kind
        |> Index.specs()
        |> Enum.each(fn %{"spec" => spec} = spec0 ->
          encoded = Elementary.Encoder.encode!(spec)

          spec0
          |> Map.put("spec", encoded)
          |> Index.put()
        end)
      end)

      send(owner, {:total, length(specs)})
    end)

    receive do
      {:total, count} ->
        Logger.info("Compiled #{count} specs")
    after
      1_000 ->
        compile()
    end
  end
end

# defp compile(_, %{"kind" => "test", "name" => name, "spec" => spec}) do
#   registered_name = String.to_atom("#{name}_test")
#   debug = spec["debug"] == true

#   [
#     {module_name(name, "test"),
#      quote do
#        use GenServer
#        require Logger
#        @name unquote(name)
#        @test unquote(registered_name)
#        @timeout 1000
#        @scenarios unquote(Macro.escape(spec["scenarios"] || []))
#        @init unquote(Macro.escape(spec["init"]))
#        @debug unquote(debug)

#        def name(), do: @name
#        def kind(), do: "test"

#        def child_spec(opts) do
#          %{
#            id: @test,
#            start: {__MODULE__, :start_link, [opts]},
#            type: :worker,
#            restart: :temporary,
#            shutdown: 5000
#          }
#        end

#        def start_link(opts) do
#          GenServer.start_link(__MODULE__, opts, name: @test)
#        end

#        def init(opts) do
#          settings = opts[:settings]
#          tag = opts[:tag]
#          {:ok, facts} = settings.get()

#          {:ok, init} =
#            case @init do
#              nil ->
#                {:ok, facts}

#              init_spec ->
#                {:ok, encoded} = Elementary.Encoder.encode(init_spec, facts)
#                {:ok, Map.merge(facts, encoded)}
#            end

#          scenarios = scenarios(tag)

#          Process.send_after(self(), :timeout, @timeout)

#          {:ok,
#           %{
#             log: fn _ -> :ok end,
#             started: Elementary.Kit.now(),
#             settings: settings,
#             tag: tag,
#             init: init,
#             scenarios: scenarios,
#             scenario: nil,
#             scenario_started: nil,
#             step: nil,
#             context: nil,
#             trace: %{
#               scenarios: [],
#               scenario: nil
#             },
#             report: %{
#               total: length(scenarios),
#               passed: 0,
#               failed: 0,
#               failures: []
#             }
#           }, {:continue, :scenario}}
#        end

#        def handle_continue(
#              :scenario,
#              %{init: init, trace: trace, scenarios: [current | rest]} = state
#            ) do
#          log = debug_fun(current, @debug)
#          title = current["title"]
#          log.(title)

#          {:noreply,
#           %{
#             state
#             | log: log,
#               context: init,
#               scenario: current,
#               scenario_started: Elementary.Kit.now(),
#               scenarios: rest,
#               trace: trace_with_new_scenario(trace)
#           }, {:continue, :step}}
#        end

#        def handle_continue(
#              :scenario,
#              %{started: started, log: log, trace: trace, report: report, scenarios: []} = state
#            ) do
#          report =
#            Map.merge(
#              %{
#                :test => @name,
#                :time => Elementary.Kit.duration(started, :millisecond)
#              },
#              report
#            )

#          msg = "#{inspect(report, pretty: true)}"

#          case report.failed do
#            0 -> Logger.info(msg)
#            _ -> Logger.error(msg)
#          end

#          write_trace(trace, state)

#          {:stop, :normal, state}
#        end

#        def handle_continue(
#              :step,
#              %{
#                log: log,
#                report: report,
#                context: context,
#                trace: trace,
#                scenario_started: scenario_started,
#                scenario: %{"title" => scenario_title, "steps" => [current | rest]} = scenario
#              } = state
#            ) do
#          step_title = current["title"]
#          step_spec = current["spec"]
#          scenario_id = id(scenario_title)
#          step_id = id(step_title, scenario_title)
#          started = Elementary.Kit.now()

#          case Elementary.Encoder.encode(step_spec, context) do
#            {:ok, output} ->
#              elapsed = Elementary.Kit.duration(started, :millisecond)

#              new_context =
#                case is_map(output) do
#                  true -> Map.merge(context, output)
#                  false -> context
#                end

#              scenario = Map.put(scenario, "steps", rest)
#              log.("#{step_title} (#{elapsed}ms)")
#              log.("    #{inspect(output)}")

#              step_trace = %{
#                title: step_title,
#                id: step_id,
#                scenario: scenario_id,
#                status: :success,
#                time: elapsed,
#                spec: step_spec,
#                context: context,
#                output: output
#              }

#              {:noreply,
#               %{
#                 state
#                 | trace: trace_with_step(trace, step_trace),
#                   context: new_context,
#                   step: nil,
#                   scenario: scenario
#               }, {:continue, :step}}

#            {:error, e} ->
#              elapsed = Elementary.Kit.duration(started, :millisecond)
#              scenario_elapsed = Elementary.Kit.duration(scenario_started, :millisecond)
#              scenario = Map.put(scenario, "steps", [])
#              failures = report.failures

#              report = %{
#                report
#                | failures: [scenario_title | failures],
#                  failed: report.failed + 1
#              }

#              step_trace = %{
#                title: step_title,
#                id: step_id,
#                scenario: scenario_id,
#                status: :error,
#                time: elapsed,
#                spec: step_spec,
#                context: context,
#                output: e
#              }

#              scenario_trace = %{
#                title: scenario_title,
#                status: :error,
#                time: scenario_elapsed
#              }

#              Logger.error(
#                "#{
#                  inspect(
#                    step_trace,
#                    pretty: true
#                  )
#                }"
#              )

#              trace =
#                trace
#                |> trace_with_step(step_trace)
#                |> trace_with_scenario(scenario_trace)

#              {:noreply,
#               %{
#                 state
#                 | trace: trace,
#                   report: report,
#                   step: nil,
#                   scenario: scenario
#               }, {:continue, :scenario}}
#          end
#        end

#        def handle_continue(
#              :step,
#              %{
#                report: report,
#                trace: trace,
#                log: log,
#                scenario_started: started,
#                scenario: %{"title" => title, "steps" => []} = scenario
#              } = state
#            ) do
#          elapsed = Elementary.Kit.duration(started, :millisecond)
#          Logger.info("Scenario \"#{title}\" (#{elapsed}ms)")
#          report = %{report | passed: report.passed + 1}

#          scenario_trace = %{
#            title: title,
#            status: :success,
#            time: elapsed,
#            id: id(title),
#            tags: scenario["tags"] || []
#          }

#          {:noreply,
#           %{state | trace: trace_with_scenario(trace, scenario_trace), report: report},
#           {:continue, :scenario}}
#        end

#        def handle_info(:timeout, %{log: log} = state) do
#          log.("Test #{@name} timeout")
#          {:stop, :normal, state}
#        end

#        def scenarios(nil) do
#          @scenarios
#        end

#        def scenarios(tag) do
#          Enum.filter(@scenarios, fn scenario ->
#            Enum.member?(scenario["tags"] || [], tag)
#          end)
#        end

#        defp debug_fun(_, true) do
#          fn msg ->
#            Logger.info(msg)
#          end
#        end

#        defp debug_fun(spec, _) do
#          case Enum.member?(spec["tags"] || [], "debug") do
#            true ->
#              debug_fun(spec, true)

#            _ ->
#              fn _ -> :ok end
#          end
#        end

#        defp trace_with_new_scenario(trace) do
#          %{trace | scenario: %{steps: []}}
#        end

#        defp trace_with_scenario(
#               %{scenarios: scenarios, scenario: %{steps: steps}} = trace,
#               scenario_trace
#             ) do
#          scenario_trace =
#            scenario_trace
#            |> Map.put(:steps, Enum.reverse(steps))

#          %{
#            trace
#            | scenarios: [scenario_trace | scenarios],
#              scenario: nil
#          }
#        end

#        defp trace_with_step(
#               %{scenario: %{steps: steps} = scenario} = trace,
#               step_trace
#             ) do
#          %{trace | scenario: %{scenario | steps: [step_trace | steps]}}
#        end

#        defp write_trace(%{scenarios: scenarios} = trace, _) do
#          path = "#{Elementary.Kit.assets()}/tests.json"
#          scenarios = Enum.reverse(scenarios)
#          File.write!(path, Jason.encode!(scenarios))
#          Logger.info("Written #{path}")
#        end

#        defp id(title) do
#          "#{:erlang.phash2(title)}"
#        end

#        defp id(title, parent) do
#          id(parent <> title)
#        end
#      end}
#   ]
# end

# defp compile(_specs, _), do: []

# defp defmod(mod, content) do
#   :code.purge(mod)
#   :code.delete(mod)
#   {:module, mod, _, _} = Module.create(mod, content, Macro.Env.location(__ENV__))
#   {:ok, mod}
# end

# def port_module_name(name), do: module_name(name, "port")
# def app_module_name(name), do: module_name(name, "app")
# def settings_module_name(name), do: module_name(name, "settings")
# def store_module_name(name), do: module_name(name, "store")
# defp module_name(name, kind), do: Kit.module_name([name, kind])
