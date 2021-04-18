defmodule Elementary.Stores do
  @moduledoc false

  use Supervisor
  alias Elementary.{Kit, Index, Encoder}
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    Index.specs("store")
    |> Enum.map(fn %{"name" => name} = spec ->
      name = String.to_atom(name)
      IO.inspect(store: name)
      store_spec(spec)
    end)
    |> Supervisor.init(strategy: :one_for_one)
  end

  def store_name(%{"name" => name}), do: store_name(name)
  def store_name(name) when is_atom(name), do: name
  def store_name(name), do: String.to_existing_atom(name)

  def store_spec(%{"name" => name, "spec" => spec}) do
    name = store_name(name)

    pool_size = spec["pool"] || 1

    {:ok, url_spec} = Encoder.encode(spec["url"] || %{"db" => name})
    url = Kit.mongo_url(url_spec)

    %{
      id: name,
      start:
        {Mongo, :start_link,
         [
           [
             timeout: 5000,
             pool_timeout: 8000,
             name: name,
             url: url,
             pool_size: pool_size
           ]
         ]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  defmodule Store do
    require Logger
    alias Elementary.{Stores, Kit}

    @dialyzer {:no_return, {:ping, 0}}

    def empty(%{"spec" => %{"collections" => cols}} = spec) do
      Enum.reduce_while(cols, :ok, fn {col, _}, _ ->
        case empty_collection(spec, col) do
          :ok ->
            {:cont, :ok}

          {:error, e} ->
            {:halt, mongo_error(e)}
        end
      end)
    end

    defp empty_collection(spec, col) do
      case spec |> Stores.store_name() |> Mongo.delete_many(col, %{}) do
        {:ok, _} ->
          :ok

        {:error, e} ->
          {:halt, mongo_error(e)}
      end
    end

    def reset(%{"spec" => %{"collections" => cols}} = spec) do
      Enum.reduce_while(cols, :ok, fn {col, col_spec}, _ ->
        with :ok <- drop_collection(spec, col),
             :ok <- ensure_collection(spec, col, col_spec),
             :ok <- ensure_indexes(spec, col, col_spec["indexes"] || []),
             :ok <- ensure_data(spec, col, col_spec["data"] || []) do
          {:cont, :ok}
        else
          {:error, e} ->
            {:halt, mongo_error(e)}
        end
      end)
    end

    def ensure_collection(spec, col, col_spec) do
      opts = collection_create_opts(col_spec)

      with {:error, %Mongo.Error{code: 48}} <-
             spec |> Stores.store_name() |> Mongo.create(col, opts) do
        :ok
      end
    end

    defp collection_create_opts(%{"max" => max, "size" => size}) do
      [capped: true, max: max, size: size]
    end

    defp collection_create_opts(_), do: []

    def drop_collection(spec, col) do
      case spec |> Stores.store_name() |> Mongo.drop_collection(col) do
        :ok ->
          :ok

        {:error, %{code: 26}} ->
          :ok

        {:error, e} ->
          {:error, mongo_error(e)}
      end
    end

    def ensure_indexes(spec, col, indices) do
      Enum.each(indices, fn index ->
        ensure_index(spec, col, index)
      end)
    end

    def index_spec(%{"lookup" => field}) when is_binary(field) do
      {"_#{field}_", [unique: false, key: [{field, 1}]]}
    end

    def index_spec(%{"unique" => field}) when is_binary(field) do
      {"_#{field}_", [unique: true, key: [{field, 1}]]}
    end

    def index_spec(%{"unique" => fields}) when is_list(fields) do
      {Enum.join([""] ++ fields ++ [""], "_"),
       [unique: true, key: Enum.map(fields, fn f -> {f, 1} end)]}
    end

    def index_spec(%{"geo" => field}) do
      {"_#{field}_", [key: %{field => "2dsphere"}]}
    end

    def index_spec(%{"expire" => field, "after" => seconds}) do
      {"_#{field}_", [expireAfterSeconds: seconds, key: [{field, 1}]]}
    end

    def ensure_index(spec, col, index) do
      {name, opts} = index_spec(index)

      with {:ok, _} <-
             spec
             |> Stores.store_name()
             |> Mongo.command(
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

    def ensure_data(_spec, _col, []), do: :ok

    def ensure_data(spec, col, [%{"id" => id} = doc | rest]) do
      with {:ok, _} <- ensure(spec, col, %{"id" => id}, doc) do
        IO.inspect(
          col: col,
          doc: id
        )

        ensure_data(spec, col, rest)
      end
    end

    def ping(spec) do
      case spec |> Stores.store_name() |> Mongo.ping() do
        {:ok, _} ->
          :ok

        {:error, e} ->
          {:error, mongo_error(e)}
      end
    end

    def stats(spec) do
      store = spec |> Stores.store_name()

      {:ok,
       store
       |> Mongo.show_collections()
       |> Enum.to_list()
       |> Enum.reduce(%{}, fn col, acc ->
         count =
           case Mongo.estimated_document_count(store, col, []) do
             {:ok, count} ->
               count

             _ ->
               -1
           end

         Map.put(acc, col, count)
       end)}
      |> IO.inspect()
    end

    def insert(spec, col, doc) when is_map(doc) do
      doc = Kit.with_mongo_id(doc)

      case spec
           |> Stores.store_name()
           |> Mongo.insert_one(
             col,
             doc
           ) do
        {:ok, _} ->
          :ok

        {:error, e} ->
          {:error, mongo_error(e)}
      end
    rescue
      e ->
        {:error, mongo_error(e)}
    catch
      :exit, e ->
        {:error, mongo_error(e)}
    end

    def insert(spec, col, docs) when is_list(docs) do
      docs = Enum.map(docs, &Kit.with_mongo_id(&1))

      case spec
           |> Stores.store_name()
           |> Mongo.insert_many(
             col,
             docs
           ) do
        {:ok, _} ->
          :ok

        {:error, e} ->
          {:error, mongo_error(e)}
      end
    rescue
      e ->
        {:error, mongo_error(e)}
    catch
      :exit, e ->
        {:error, mongo_error(e)}
    end

    def subscribe(spec, col, partition, %{"offset" => offset}, fun, opts \\ []) do
      opts = opts |> Keyword.put(:started, Kit.millis())

      pipeline = [
        %{
          "$match" => %{
            "operationType" => "insert",
            "fullDocument.p" => partition
          }
        }
      ]

      resume_token_fn = fn
        %{"_data" => offset} ->
          fun.(%{"offset" => offset})

        other ->
          Logger.warn("Unexpected resume token #{inspect(other)} from collection #{col}")
      end

      doc_fn = fn
        %{"fullDocument" => doc} ->
          fun.(%{"data" => Kit.without_mongo_id(doc)})

        other ->
          Logger.warn("unexpected change stream doc #{inspect(other)}")
      end

      opts =
        case offset do
          "" ->
            opts

          offset ->
            Keyword.put(opts, :start_after, %{"_data" => offset})
        end

      pid =
        spawn_link(fn ->
          spec
          |> Stores.store_name()
          |> Mongo.watch_collection(col, pipeline, resume_token_fn, opts)
          |> Enum.each(doc_fn)
        end)

      {:ok, pid}
    end

    def ensure(spec, col, where, doc) do
      update(spec, col, where, doc, true)
    end

    def update(spec, col, where, doc, upsert \\ false) when is_map(doc) do
      where = Kit.with_mongo_id(where)

      doc =
        Kit.with_mongo_id(doc)
        |> update_spec()

      try do
        spec
        |> Stores.store_name()
        |> Mongo.update_one(
          col,
          where,
          doc,
          upsert: upsert
        )
      rescue
        e ->
          {:error, e}
      end
      |> case do
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
    end

    def update_many(spec, col, where, doc) do
      where = Kit.with_mongo_id(where)

      doc =
        Kit.with_mongo_id(doc)
        |> update_spec()

      try do
        spec
        |> Stores.store_name()
        |> Mongo.update_many(
          col,
          where,
          doc
        )
      rescue
        e ->
          {:error, e}
      end
      |> case do
        {:ok,
         %Mongo.UpdateResult{
           modified_count: modified
         }} ->
          {:ok, modified}

        {:error, e} ->
          {:error, mongo_error(e)}
      end
    end

    def find_all(spec, col, query, opts \\ []) do
      opts = with_sort(opts)

      opts =
        Keyword.merge(opts,
          skip: Keyword.get(opts, :offset, 0),
          limit: Keyword.get(opts, :limit, 20)
        )

      query = Kit.with_mongo_id(query)

      {:ok,
       spec
       |> Stores.store_name()
       |> Mongo.find(col, query, opts)
       |> Stream.map(&Kit.without_mongo_id(&1))
       |> Enum.to_list()}
    end

    defp with_sort(opts) do
      case opts[:sort] do
        nil ->
          opts

        sort ->
          Keyword.put(
            opts,
            :sort,
            Enum.map(sort, fn
              {k, "asc"} ->
                {k, 1}

              {k, "desc"} ->
                {k, -1}
            end)
          )
      end
    end

    defp update_spec(%{"$unset" => _} = doc), do: doc
    defp update_spec(%{"$push" => _} = doc), do: doc
    defp update_spec(%{"$pull" => _} = doc), do: doc
    defp update_spec(doc), do: [%{"$set" => doc}]

    def find_one(spec, col, query, opts \\ []) do
      store = Stores.store_name(spec)
      query = Kit.with_mongo_id(query)

      {res, _} =
        case opts[:delete] do
          true ->
            {Mongo.find_one_and_delete(store, col, query), :find_one_and_delete}

          _ ->
            {Mongo.find_one(store, col, query), :find_one}
        end

      case res do
        nil ->
          {:error, :not_found}

        {:error, e} ->
          {:error, mongo_error(e)}

        doc ->
          {:ok, Kit.without_mongo_id(doc)}
      end
    end

    def find_one_and_update(spec, col, query, update, opts) do
      store = Stores.store_name(spec)
      query = Kit.with_mongo_id(query)
      opts = with_sort(opts)

      update = update_spec(update)

      case Mongo.find_one_and_update(store, col, query, update, opts) do
        {:ok, nil} ->
          {:error, :not_found}

        {:ok, item} ->
          {:ok, Kit.without_mongo_id(item)}

        {:error, e} ->
          {:error, mongo_error(e)}
      end
    end

    def aggregate(spec, col, p, opts \\ []) do
      store = Stores.store_name(spec)

      opts =
        opts
        |> Keyword.put(:started, Kit.millis())

      p = pipeline(p)

      {:ok,
       Mongo.aggregate(store, col, p, opts)
       |> Stream.map(&Kit.without_mongo_id(&1))
       |> Enum.to_list()}
    end

    defp pipeline(items) do
      Enum.map(items, &pipeline_item(&1))
    end

    defp pipeline_item(%{"$match" => query}) do
      %{"$match" => Kit.with_mongo_id(query)}
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

    def delete(spec, col, doc) when is_map(doc) do
      store = Stores.store_name(spec)

      doc = Kit.with_mongo_id(doc)

      case Mongo.delete_one(
             store,
             col,
             doc
           ) do
        {:ok, %Mongo.DeleteResult{acknowledged: true, deleted_count: deleted}} ->
          {:ok, deleted}

        {:error, e} ->
          {:error, mongo_error(e)}
      end
    end

    def count(spec, col, where) do
      store = Stores.store_name(spec)
      where = Kit.with_mongo_id(where)

      with {:error, e} <- Mongo.count_documents(store, col, where) do
        {:error, mongo_error(e)}
      end
    end

    defp mongo_error(%DBConnection.ConnectionError{}) do
      :connection_error
    end

    defp mongo_error(%Mongo.Error{code: 10107, host: nil, message: _}) do
      :connection_error
    end

    defp mongo_error(%{write_errors: [error]}) do
      mongo_error(error)
    end

    defp mongo_error(%{"code" => 11000}) do
      :conflict
    end

    defp mongo_error({:timeout, _}), do: :timeout

    defp mongo_error(
           {{:bad_return_value, :error},
            {GenServer, :call, [_, {:checkout_session, :write, :implicit, _}, _]}}
         ) do
      :connection_error
    end

    defp mongo_error({:normal, {DBConnection.Holder, :checkout, _}}) do
      :connection_error
    end

    defp mongo_error(error) do
      Logger.warn("Got unknown mongo error #{inspect(error)}")
      :unknown
    end
  end
end
