defmodule Elementary.Graph do
  @moduledoc false

  use Elementary.Provider
  alias(Elementary.{Kit})

  defstruct rank: :high,
            name: "",
            version: "1",
            store: nil,
            settings: [],
            entities: []

  defmodule Http do
    defmacro __using__(graph: graph) do
      quote do
        @graph unquote(graph)
        @schema unquote(Elementary.Graph.graphql_schema(graph))

        def graph(), do: @graph
        def protocol(), do: :http
        def permanent(), do: false

        def init(req, state) do
          t0 = System.system_time(:microsecond)
          {:ok, query, req} = query(req)

          {absinthe, {:ok, reply}} =
            :timer.tc(fn ->
              Absinthe.run(
                query,
                @schema
              )
            end)

          elapsed = System.system_time(:microsecond) - t0

          req =
            :cowboy_req.reply(
              200,
              %{
                "content-type" => "application/json",
                "elementary-app" => "#{@graph}",
                "elementary-micros" => "#{elapsed}",
                "absinthe-micros" => "#{absinthe}"
              },
              Jason.encode!(reply),
              req
            )

          {:ok, req, state}
        end

        defp query(req) do
          {:ok, data, req} = :cowboy_req.read_body(req)

          case Jason.decode(data) do
            {:ok, %{"query" => q}} ->
              {:ok, q, req}

            {:error, _} ->
              {:ok, data, req}
          end
        end
      end
    end
  end

  defmodule Graphiql do
    defmacro __using__(graph: graph, path: path) do
      quote do
        @graph unquote(graph)
        @html unquote("""
              <!DOCTYPE html><html><head><link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/graphiql/0.15.1/graphiql.css" /><script src="https://cdnjs.cloudflare.com/ajax/libs/fetch/1.1.0/fetch.min.js"></script><script src="https://cdnjs.cloudflare.com/ajax/libs/react/15.5.4/react.min.js"></script><script src="https://cdnjs.cloudflare.com/ajax/libs/react/15.5.4/react-dom.min.js"></script><script src="https://cdnjs.cloudflare.com/ajax/libs/graphiql/0.15.1/graphiql.js"></script></head><body style="width: 100%; height: 100%; margin: 0; overflow: hidden;"><div id="graphiql" style="height: 100vh;">Loading...</div><script>function graphQLFetcher(graphQLParams) {return fetch("#{
                path
              }", {method: "post",body: JSON.stringify(graphQLParams),credentials: "include",}).then(function (response) {return response.text();}).then(function (responseBody) {try {return JSON.parse(responseBody);} catch (error) {return responseBody;}});}ReactDOM.render(React.createElement(GraphiQL, {fetcher: graphQLFetcher}),document.getElementById("graphiql"));</script></body></html>
              """)

        def init(req, state) do
          req =
            :cowboy_req.reply(
              200,
              %{
                "content-type" => "text/html",
                "elementary-app" => "#{@graph}"
              },
              @html,
              req
            )

          {:ok, req, state}
        end
      end
    end
  end

  def parse(
        %{"version" => version, "kind" => "graph", "name" => name, "spec" => spec},
        _
      ) do
    settings =
      case spec do
        %{"settings" => settings} ->
          [name | settings]

        _ ->
          [name]
      end

    with {:ok, store} <- parse_store(spec) do
      {:ok,
       %__MODULE__{
         name: String.to_atom(name),
         version: version,
         settings: Enum.uniq(settings),
         store: store
       }}
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  def parse_store(%{"store" => store}) do
    {:ok, String.to_atom(store)}
  end

  def parse_store(spec) do
    {:error, %{spec: spec, reason: :missing_store}}
  end

  def graphql_schema(name) do
    Module.concat([
      Kit.camelize([name, "Graph"])
    ])
  end

  def ast(graph, index) do
    entities = graph_entities(index, graph)

    [
      {:module, graphql_schema(graph.name),
       [
         {:usage, Elementary.Graph,
          [
            graph: graph.name,
            entities: entities
          ]}
       ]}
    ]
  end

  defmacro __using__(opts) do
    ast1 =
      quote do
        use Absinthe.Schema

        @graph unquote(opts[:graph])
        @entities unquote(opts[:entities])

        def kind(), do: :graph
        def name(), do: @graph
        def entities(), do: @entities
      end

    ast2 =
      Enum.map(opts[:entities], fn e ->
        quote do
          import_types(unquote(Elementary.Entity.types(e)))
        end
      end)

    ast3 =
      quote do
        object :op do
          field(:ref, :id)
        end

        query name: "Query" do
          unquote(
            Enum.map(opts[:entities], fn e ->
              quote do
                import_fields(unquote(Elementary.Entity.queries(e)))
              end
            end)
          )
        end

        mutation name: "Mutation" do
          unquote(
            Enum.map(opts[:entities], fn e ->
              quote do
                import_fields(unquote(Elementary.Entity.mutations(e)))
              end
            end)
          )
        end
      end

    List.flatten([ast1, ast2, ast3])
  end

  def indexed(mods) do
    {:module, Elementary.Index.Graph,
     (mods
      |> Enum.filter(fn m ->
        m.kind() == :graph
      end)
      |> Enum.flat_map(fn m ->
        res = {:tuple, [:ok, m]}

        [
          {:fun, :get, [{:symbol, m.name()}], res},
          {:fun, :get, [{:text, m.name()}], res}
        ]
      end)) ++
       [
         {:fun, :get, [{:var, :_}], {:tuple, [:error, :not_found]}}
       ]}
    |> Elementary.Ast.compiled()
  end

  defp graph_entities(asts, graph) do
    Elementary.Ast.filter(asts, {:kind, :entity})
    |> Enum.filter(fn mod ->
      [{_, _, _, g}] = Elementary.Ast.filter(mod, {:fun, :graph})
      g == graph.name
    end)
    |> Enum.map(fn mod ->
      [{_, _, _, name}] = Elementary.Ast.filter(mod, {:fun, :name})
      name
    end)
  end
end
