defmodule Elementary.Store do
  @moduledoc false

  use Elementary.Provider
  alias(Elementary.{Kit})

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

      def write(entry, col \\ "events") do
        with {:ok,
              %Mongo.InsertOneResult{
                inserted_id: id
              }} <- Mongo.insert_one(@store, col, entry) do
          {:ok, BSON.ObjectId.encode!(id)}
        end
      end

      def stream(fun, col \\ "events") do
        spawn_link(fn ->
          cursor = Mongo.find(@store, col, %{})
          cursor |> Enum.each(fun)
          cursor = Mongo.watch_collection(@store, col, [], fn _ -> nil end, [])

          cursor
          |> Enum.each(fn %{"fullDocument" => doc} -> fun.(doc) end)
        end)
      end
    end
  end
end
