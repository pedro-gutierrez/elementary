defmodule Elementary.Port do
  @moduledoc false

  use Elementary.Provider

  alias Elementary.{Kit, Mount}

  defstruct rank: :high,
            name: "",
            version: "1",
            port: 8080,
            apps: []

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
         {:ok, apps} <- parse_apps(spec) do
      {:ok,
       %__MODULE__{
         name: String.to_atom(name),
         version: version,
         port: port,
         apps: apps
       }}
    else
      {:error, e} ->
        {:error, %{spec: spec0, reason: e}}
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  defp parse_port(spec) do
    {:ok, Map.get(spec, "port", 8080)}
  end

  defp parse_apps(spec) do
    Mount.parse(Map.get(spec, "apps", []))
  end

  def ast(port, _) do
    [
      {:module, [port.name, "port"] |> Kit.camelize(),
       [
         {:usage, Elementary.Port,
          [
            name: port.name,
            port: port.port,
            apps:
              Enum.map(port.apps, fn %{app: app, path: path, protocol: :http} ->
                [handler: Elementary.Http.Handler, path: path, app: app]
              end)
          ]},
         {:fun, :kind, [], :port},
         {:fun, :name, [], {:symbol, port.name}},
         {:fun, :supervised, [], {:boolean, true}}
       ]}
    ]
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
             Enum.map(apps, fn mount ->
               {:ok, app} = Elementary.Index.App.get(mount[:app])
               {:ok, settings} = app.settings()
               {mount[:path], mount[:handler], [mount[:app], app, settings]}
             end)}
          ])

        {:ok, pid} =
          :cowboy.start_clear(
            name,
            [{:port, port}],
            %{:env => %{:dispatch => dispatch}}
          )

        IO.inspect(
          port: name,
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
