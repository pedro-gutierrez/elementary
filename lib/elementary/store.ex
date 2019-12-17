defmodule Elementary.Store do
  @moduledoc false

  use Elementary.Provider
  alias(Elementary.{Kit, Ast})

  defstruct rank: :high,
            name: "",
            version: "1",
            pool: 1,
            url: nil

  def parse(
        %{"version" => version, "kind" => "store", "name" => name, "spec" => spec},
        _
      ) do
    with {:ok, url} <- parse_url(Map.put(spec, "db", name)),
         {:ok, pool} <- parse_pool(spec) do
      {:ok,
       %__MODULE__{
         name: name,
         version: version,
         url: url,
         pool: pool
       }}
    end
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

  defp parse_url(%{
         "scheme" => scheme,
         "username" => username,
         "password" => password,
         "host" => host,
         "db" => db,
         "options" => options
       }) do
    params =
      Enum.reduce(options, [], fn {k, v}, opts ->
        ["#{k}=#{v}" | opts]
      end)
      |> Enum.join("&")

    {:ok, "#{scheme}://#{username}:#{password}@#{host}/#{db}?#{params}"}
  end

  defp parse_pool(%{"pool" => pool}) do
    {:ok, pool}
  end

  def store_name(name) do
    Module.concat([
      Kit.camelize([name, "Store"])
    ])
  end

  def ast(store, _) do
    store_name = store_name(store.name)

    [
      {:module, store_name,
       [
         {:fun, :kind, [], :store},
         {:fun, :name, [], {:symbol, store.name}},
         {:fun, :supervised, [], {:boolean, true}},
         {:usage, __MODULE__,
          [
            name: store_name,
            pool: store.pool,
            url: store.url
          ]}
       ]}
    ]
  end

  defmacro __using__(opts) do
    quote do
      @store unquote(opts[:name])
      @events "events"
      @commands "commands"

      def store(), do: @store

      def child_spec(_) do
        %{
          id: @store,
          start:
            {Mongo, :start_link,
             [
               [
                 name: @store,
                 url: unquote(opts[:url]),
                 pool_size: unquote(opts[:pool])
               ]
             ]},
          type: :worker,
          restart: :permanent,
          shutdown: 5000
        }
      end

      def write_command(kind, name, %{id: id} = data) do
        write_command(kind, name, id, Map.drop(data, [:id]))
      end

      def write_command(kind, name, id, data) do
        write(@commands, kind, name, id, data)
      end

      def write_event(kind, name, id, data) do
        write(@events, kind, name, id, data)
      end

      def write(%{"kind" => kind, "event" => name, "id" => id, "data" => data}) do
        write(@events, kind, name, id, data)
      end

      defp write(col, kind, name, id, data, partition \\ 0) do
        with {:ok,
              %Mongo.InsertOneResult{
                inserted_id: _
              }} <-
               Mongo.insert_one(
                 @store,
                 col,
                 %{
                   kind: kind,
                   event: name,
                   id: id,
                   partition: partition,
                   ts: Elementary.Kit.now(),
                   node: Node.self(),
                   data: data
                 }
               ) do
          {:ok, id}
        end
      end

      defp sanitized(doc) do
        Map.drop(doc, ["_id"])
      end

      def replay(fun, col \\ @events) do
        spawn_link(fn ->
          cursor = Mongo.find(@store, col, %{})

          cursor
          |> Enum.each(fn doc ->
            fun.(sanitized(doc))
          end)

          watch(fun, col)
        end)
      end

      def watch(fun, col \\ @events) do
        Mongo.watch_collection(@store, col, [], fn _ -> nil end, [])
        |> Enum.each(fn %{"fullDocument" => doc} ->
          fun.(sanitized(doc))
        end)
      end
    end
  end

  use Elementary.Effect, :store

  def effect(owner, %{"kind" => kind, "event" => name, "id" => id, "data" => data, "in" => store}) do
    with {:ok, store} <- Elementary.Index.Store.get(store),
         {:ok, _} <- store.write_event(kind, name, id, data) do
      %{"status" => "ok", "written" => id, "store" => store}
    else
      {:error, reason} ->
        %{"status" => "error", "store" => store, "reason" => reason}
    end
    |> update(owner)
  end

  def indexed(mods) do
    Ast.index(mods, Elementary.Index.Store, :store)
    |> Ast.compiled()
  end
end
