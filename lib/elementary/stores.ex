defmodule Elementary.Stores do
  @moduledoc false

  use Supervisor
  alias Elementary.{Kit, Index, Encoder}

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
      opts = [started: Kit.millis()]

      case spec |> Stores.store_name() |> Mongo.ping() do
        {:ok, _} ->
          :ok

        {:error, e} ->
          {:error, mongo_error(e)}
      end
      |> log(%{"op" => "ping"}, spec, opts)
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

    def insert(spec, col, doc, opts \\ []) when is_map(doc) do
      opts = opts |> Keyword.put(:started, Elementary.Kit.millis())
      doc = Elementary.Kit.with_mongo_id(doc)

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
      |> log(
        %{"col" => col, "op" => "insert", "doc" => doc},
        spec,
        opts
      )
    end

    def subscribe(spec, col, %{"offset" => offset}, fun, opts \\ []) do
      opts = opts |> Keyword.put(:started, Elementary.Kit.millis())
      pipeline = []

      resume_token_fn = fn %{"_data" => offset} ->
        fun.(%{"offset" => offset})
      end

      doc_fn = fn
        %{"fullDocument" => doc} ->
          fun.(%{"data" => Elementary.Kit.without_mongo_id(doc)})

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
      started = Elementary.Kit.millis()
      where = Elementary.Kit.with_mongo_id(where)

      doc =
        Elementary.Kit.with_mongo_id(doc)
        |> case do
          %{"$push" => _} = doc -> doc
          %{"$pull" => _} = doc -> doc
          doc -> %{"$set" => doc}
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
      |> log(
        %{
          "col" => col,
          "op" => "update",
          "where" => "where",
          "doc" => doc,
          "upsert" => upsert
        },
        spec,
        started: started
      )
    end

    def find_all(spec, col, query, opts \\ []) do
      started = Elementary.Kit.millis()

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

      query = Elementary.Kit.with_mongo_id(query)

      {:ok,
       spec
       |> Stores.store_name()
       |> Mongo.find(col, query, opts)
       |> Stream.map(&Elementary.Kit.without_mongo_id(&1))
       |> Enum.to_list()}
      |> log(
        %{"col" => col, "op" => "find", "where" => query, "opts" => opts},
        spec,
        started: started,
        data: :summary
      )
    end

    def find_one(spec, col, query, opts \\ []) do
      store = Stores.store_name(spec)
      opts = opts |> Keyword.put(:started, Elementary.Kit.millis())
      query = Elementary.Kit.with_mongo_id(query)

      {res, op} =
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
          {:ok, Elementary.Kit.without_mongo_id(doc)}
      end
      |> log(%{"col" => col, "op" => op, "where" => query}, spec, opts)
    end

    defp log(data, meta, spec, opts) do
      if :enable == (opts[:log] || :enable) do
        meta
        |> with_log_payload(data, spec, opts[:data] || :full)
        |> with_log_duration(spec, opts)
        |> with_log_meta(spec)
        |> Elementary.Logger.log()
      end

      data
    end

    defp with_log_payload(meta, {:ok, data}, _, :summary) when is_list(data) do
      Map.put(meta, "result", %{"list" => %{"size" => length(data)}})
    end

    defp with_log_payload(meta, {:ok, data}, _, _) do
      Map.put(meta, "result", data)
    end

    defp with_log_payload(meta, {:error, reason}, _, _) do
      Map.put(meta, "result", reason)
    end

    defp with_log_payload(meta, other, _, _) do
      Map.put(meta, "result", other)
    end

    defp with_log_duration(meta, _, opts) do
      case opts[:started] do
        nil ->
          meta

        started ->
          Map.put(meta, "duration", Elementary.Kit.millis_since(started))
      end
    end

    defp with_log_meta(meta, %{"name" => name}) do
      Map.merge(meta, %{
        "kind" => "store",
        "name" => name
      })
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
