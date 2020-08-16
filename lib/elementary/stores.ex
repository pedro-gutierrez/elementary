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
    |> Enum.map(&store_spec(&1))
    |> Supervisor.init(strategy: :one_for_one)
  end

  def store_name(%{"name" => name}), do: store_name(name)
  def store_name(name), do: String.to_atom("#{name}_store")

  defp store_spec(%{"name" => name, "spec" => spec}) do
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
          Logger.warn("Unexpected offset #{inspect(other)} from collection #{col}")
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
        |> case do
          %{"$push" => _} = doc -> doc
          %{"$pull" => _} = doc -> doc
          doc -> [%{"$set" => doc}]
        end

      case spec
           |> Stores.store_name()
           |> Mongo.update_one(
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
    end

    def find_all(spec, col, query, opts \\ []) do
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

      query = Kit.with_mongo_id(query)

      {:ok,
       spec
       |> Stores.store_name()
       |> Mongo.find(col, query, opts)
       |> Stream.map(&Kit.without_mongo_id(&1))
       |> Enum.to_list()}
    end

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

        doc ->
          {:ok, Kit.without_mongo_id(doc)}
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

    defp mongo_error(%DBConnection.ConnectionError{}) do
      :connection_error
    end

    defp mongo_error(%{write_errors: [error]}) do
      mongo_error(error)
    end

    defp mongo_error(%{"code" => 11000}) do
      :conflict
    end
  end
end
