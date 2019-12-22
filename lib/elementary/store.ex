defmodule Elementary.Store do
  @moduledoc false

  use Elementary.Provider
  alias(Elementary.{Kit, Ast})

  defstruct rank: :high,
            name: nil,
            version: "1"

  def parse(
        %{"version" => version, "kind" => "store", "name" => name},
        _
      ) do
    {:ok,
     %__MODULE__{
       name: String.to_atom(name),
       version: version
     }}
  end

  def parse(spec, _), do: Kit.error(:not_supported, spec)

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
         {:fun, :name, [], store.name},
         {:fun, :supervised, [], {:boolean, true}},
         {:usage, __MODULE__,
          [
            settings: store.name,
            name: store_name
          ]}
       ]}
    ]
  end

  alias Elementary.Index.App, as: Apps
  alias Elementary.Index.Store, as: Stores
  alias Elementary.Index.Entity, as: Entities

  def init_all() do
    Apps.all()
    |> Enum.each(fn app ->
      {:ok, app} = Apps.get(app)

      with {:ok, store} <- Stores.get(app),
           entities <- app.entities() do
        store.collection(:log)
        store.index(:log, :pkey, [:id, :version])

        Enum.each(entities, fn e ->
          {:ok, entity} = Entities.get(e)
          entity.init(store)
        end)
      end
    end)
  end

  def parse_url(%{
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

  def parse_pool(%{"pool" => pool}) do
    {:ok, pool}
  end

  defmacro __using__(opts) do
    quote do
      @settings unquote(opts[:settings])
      @store unquote(opts[:name])

      def store(), do: @store

      def child_spec(_) do
        {:ok, %{"store" => spec}} = Elementary.Index.Settings.get(@settings)

        {:ok, url} = Elementary.Store.parse_url(spec)
        {:ok, pool} = Elementary.Store.parse_pool(spec)

        %{
          id: @store,
          start:
            {Mongo, :start_link,
             [
               [
                 name: @store,
                 url: url,
                 pool_size: pool
               ]
             ]},
          type: :worker,
          restart: :permanent,
          shutdown: 5000
        }
      end

      def all(col, query, opts) do
        {:ok,
         Mongo.find(@store, col, query,
           skip: Keyword.get(opts, :offset, 0),
           limit: Keyword.get(opts, :limit, 20)
         )
         |> Stream.map(&sanitized(&1))
         |> Enum.to_list()}
      end

      def first(col, query) do
        case Mongo.find_one(@store, col, query) do
          nil ->
            {:error, :not_found}

          other ->
            {:ok, sanitized(other)}
        end
      end

      def write(items) do
        Mongo.Session.with_transaction(@store, fn opts ->
          Enum.map(items, fn
            {:insert, col, doc} ->
              Mongo.insert_one(
                @store,
                col,
                doc
              )

            {:update, col, query, doc} ->
              Mongo.replace_one(
                @store,
                col,
                query,
                doc,
                upsert: true
              )

            {:delete, col, query} ->
              Mongo.delete_one(
                @store,
                col,
                query
              )
          end)
          |> Enum.reduce_while(:ok, fn
            {:ok, _}, _ ->
              {:cont, :ok}

            {:error,
             %Mongo.WriteError{
               write_errors: [
                 %{"code" => code} | _
               ]
             }},
            _ ->
              {:halt, {:error, error_for(code)}}
          end)
        end)
      end

      def index(col, name, fields) do
        with {:ok, _} <-
               Mongo.command(
                 @store,
                 [
                   createIndexes: col,
                   indexes: [
                     [name: name, unique: true, key: Enum.map(fields, fn f -> {f, 1} end)]
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

      def collection(col) do
        with {:error, %Mongo.Error{code: 48}} <- Mongo.create(@store, :log) do
          :ok
        end
      end

      def sanitized(doc) do
        Map.drop(doc, ["_id"])
      end

      defp error_for(11000), do: :conflict
      defp error_for(code), do: code
    end
  end

  def indexed(mods) do
    Ast.index(mods, Elementary.Index.Store, :store)
    |> Ast.compiled()
  end
end
