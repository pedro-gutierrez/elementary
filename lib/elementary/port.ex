defmodule Elementary.Port do
  @moduledoc false

  use Elementary.Provider

  alias Elementary.Kit
  alias Elementary.Mount

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
         name: name,
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

  def parse_port(%{"port" => port}) do
    {:ok, port}
  end

  def parse_port(spec) do
    {:error, %{spec: spec, reason: :missing_port}}
  end

  def parse_apps(%{"apps" => apps}) do
    Mount.parse(apps)
  end

  def parse_apps(_), do: {:ok, []}

  def ast(port, _) do
    [
      {:module, [port.name, "port"] |> Kit.camelize(),
       [
         {:usage, Elementary.Port,
          [
            name: port.name |> String.to_atom(),
            port: port.port,
            apps:
              port.apps
              |> Enum.map(fn mount ->
                [
                  path: mount.path,
                  handler: mount |> app_handler_module(),
                  app: mount |> app_state_machine_module()
                ]
              end)
          ]},
         {:fun, :kind, [], :port},
         {:fun, :name, [], {:symbol, port.name}},
         {:fun, :supervised, [], {:boolean, true}}
       ]}
    ] ++
      (port.apps
       |> Enum.map(fn mount ->
         {:module, mount |> app_handler_module(),
          [
            {:usage, Elementary.Http,
             [
               app: mount.app |> String.to_atom()
             ]},
            {:fun, :kind, [], :http},
            {:fun, :name, [], {:tuple, [{:symbol, port.name}, {:symbol, mount.app}]}}
          ]}
       end))
  end

  defp app_state_machine_module(%Mount{} = mount) do
    [
      "elixir.",
      mount.app,
      "state",
      "machine"
    ]
    |> Kit.camelize()
    |> String.to_atom()
  end

  defp app_handler_module(%Mount{} = mount) do
    [
      "elixir.",
      mount.app,
      mount.protocol,
      "handler"
    ]
    |> Kit.camelize()
    |> String.to_atom()
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
             |> Enum.map(fn [path: path, handler: handler, app: app] ->
               {path, handler, [app]}
             end)}
          ])

        {:ok, pid} =
          :cowboy.start_clear(
            name,
            [{:port, port}],
            %{:env => %{:dispatch => dispatch}}
          )

        IO.inspect(kind: :port, name: name, port: port)
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
