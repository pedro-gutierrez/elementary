defmodule Elementary.Port do
  @moduledoc false

  use Elementary.Provider

  alias Elementary.Kit
  alias Elementary.Mount

  defstruct rank: :high,
            name: "",
            version: "1",
            port: 8080,
            apps: [],
            graphs: []

  def parse(
        %{
          "version" => version,
          "kind" => "port",
          "name" => name,
          "spec" => spec
        } = spec0,
        _
      ) do
    with {:ok, port} <- parse_port(spec),
         {:ok, apps} <- parse_apps(spec),
         {:ok, graphs} <- parse_graphs(spec) do
      {:ok,
       %__MODULE__{
         name: name,
         version: version,
         port: port,
         apps: apps,
         graphs: graphs
       }}
    else
      {:error, e} ->
        {:error, %{spec: spec0, reason: e}}
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  defp parse_port(%{"port" => port}) do
    {:ok, port}
  end

  defp parse_port(spec) do
    {:error, %{spec: spec, reason: :missing_port}}
  end

  defp parse_apps(%{"apps" => apps}) do
    Mount.parse(apps)
  end

  defp parse_apps(_), do: {:ok, []}

  defp parse_graphs(%{"graphs" => graphs}) do
    Mount.parse(graphs)
  end

  defp parse_graphs(_), do: {:ok, []}

  def ast(port, _) do
    [
      {:module, [port.name, "port"] |> Kit.camelize(),
       [
         {:usage, Elementary.Port,
          [
            name: port.name |> String.to_atom(),
            port: port.port,
            apps:
              Enum.map(port.apps, fn mount ->
                [
                  path: mount.path,
                  handler: mount |> app_handler_module(),
                  app: mount |> app_state_machine_module()
                ]
              end) ++
                Enum.map(port.graphs, fn mount ->
                  [
                    path: mount.path,
                    handler: mount |> graphql_handler_module(),
                    app: mount.app
                  ]
                end) ++
                Enum.map(port.graphs, fn mount ->
                  [
                    path: "/graphiql/#{mount.app}",
                    handler: mount |> graphiql_handler_module(),
                    app: mount.app
                  ]
                end)
          ]},
         {:fun, :kind, [], :port},
         {:fun, :name, [], {:symbol, port.name}},
         {:fun, :supervised, [], {:boolean, true}}
       ]}
    ] ++
      Enum.map(port.apps, fn mount ->
        {:module, app_handler_module(mount),
         [
           {:usage, Elementary.Http,
            [
              app: String.to_atom(mount.app)
            ]},
           {:fun, :kind, [], :http},
           {:fun, :name, [], {:tuple, [{:symbol, port.name}, {:symbol, mount.app}]}}
         ]}
      end) ++
      Enum.flat_map(port.graphs, fn mount ->
        [
          {:module, graphql_handler_module(mount),
           [
             {:usage, Elementary.Graph.Http,
              [
                graph: String.to_atom(mount.app)
              ]},
             {:fun, :kind, [], :http},
             {:fun, :name, [], {:tuple, [{:symbol, port.name}, {:symbol, mount.app}]}}
           ]},
          {:module, graphiql_handler_module(mount),
           [
             {:usage, Elementary.Graph.Graphiql,
              [
                graph: String.to_atom(mount.app),
                path: mount.path
              ]},
             {:fun, :kind, [], :http},
             {:fun, :name, [],
              {:tuple, [{:symbol, port.name}, {:symbol, mount.app}, {:symbol, :graphiql}]}}
           ]}
        ]
      end)
  end

  defp app_state_machine_module(%Mount{} = mount) do
    Elementary.App.state_machine_name(mount.app)
  end

  defp app_handler_module(%Mount{} = mount) do
    Module.concat([
      Kit.camelize([
        mount.app,
        mount.protocol,
        "handler"
      ])
    ])
  end

  defp graphql_handler_module(%Mount{} = mount) do
    Module.concat([
      Kit.camelize([
        mount.app,
        mount.protocol,
        "graphql",
        "handler"
      ])
    ])
  end

  defp graphiql_handler_module(%Mount{} = mount) do
    Module.concat([
      Kit.camelize([
        mount.app,
        mount.protocol,
        "graphiql",
        "handler"
      ])
    ])
  end

  defmacro __using__(opts) do
    quote do
      @opts unquote(opts)

      def start_link() do
        port = @opts[:port]
        name = @opts[:name]
        apps = @opts[:apps]

        dispatch =
          :cowboy_router.compile([
            {:_,
             apps
             |> Enum.map(fn
               [path: path, handler: handler, app: app] ->
                 {path, handler, [app]}
             end)}
          ])

        {:ok, pid} =
          :cowboy.start_clear(
            name,
            [{:port, port}],
            %{:env => %{:dispatch => dispatch}}
          )

        IO.inspect(
          kind: :port,
          name: name,
          port: port,
          routes:
            Enum.map(apps, fn mount ->
              mount[:path]
            end)
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
    end
  end
end
