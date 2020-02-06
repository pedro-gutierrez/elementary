defmodule Elementary.Effect do
  @moduledoc false

  alias Elementary.Kit

  def apply("uuid", _) do
    {:ok, %{"uuid" => UUID.uuid4()}}
  end

  def apply("asset", %{"named" => name}) do
    case Elementary.Encoder.encode(name) do
      {:ok, file} ->
        {:ok, Map.put(file, "status", "ok")}

      {:error, e} ->
        {:ok, %{"status" => "error", "reason" => e}}
    end
  end

  def apply("password", %{"verify" => clear, "with" => hash}) do
    case Argon2.verify_pass(clear, hash) do
      true ->
        {:ok, %{"status" => "ok"}}

      false ->
        {:ok, %{"status" => "error"}}
    end
  end

  def apply("password", %{"hash" => clear}) do
    {:ok, %{"status" => "ok", "hash" => Argon2.hash_pwd_salt(clear)}}
  end

  def apply("store", %{"store" => store, "insert" => doc, "into" => col})
      when is_map(doc) do
    {:ok, store} = Elementary.Index.get("store", store)

    {:ok,
     case store.insert(col, doc) do
       :ok ->
         %{"status" => "created"}

       {:error, e} when is_atom(e) ->
         %{"status" => "#{e}"}
     end}
  end

  def apply("store", %{"store" => store, "from" => col, "fetch" => query, "as" => as}) do
    {:ok, store} = Elementary.Index.get("store", store)

    query = Kit.with_mongo_id(query)

    {:ok,
     case store.find_one(col, query) do
       {:ok, item} ->
         %{as => item}

       {:error, e} when is_atom(e) ->
         %{"status" => Atom.to_string(e)}
     end}
  end

  def apply("store", %{"store" => store, "from" => col, "as" => as} = spec) do
    {:ok, store} = Elementary.Index.get("store", store)

    {:ok,
     case store.find_all(col, spec["find"] || %{}) do
       {:ok, items} ->
         %{as => items}

       {:error, e} when is_atom(e) ->
         %{"status" => Atom.to_string(e)}
     end}
  end

  def apply("store", %{"reset" => %{}, "store" => store}) do
    {:ok, store} = Elementary.Index.get("store", store)

    {:ok,
     %{
       "status" =>
         case store.reset() do
           :ok ->
             "init"

           {:error, e} when is_atom(e) ->
             Atom.to_string(e)
         end
     }}
  end

  def apply("store", %{"store" => store, "upload" => data, "as" => name}) do
    {:ok, store} = Elementary.Index.get("store", store)
    stream = Kit.stream_from_data(data)

    case store.upload(name, stream) do
      {:ok, _} ->
        {:ok, %{"status" => "uploaded"}}

      {:error, e} ->
        {:ok, %{"status" => "error", "reason" => e}}
    end
  end

  def apply("test", %{"run" => test, "settings" => settings}) do
    with {:ok, _pid} <- Elementary.Test.run(test, settings) do
      {:ok, %{"status" => "started"}}
    else
      {:error, :not_found} ->
        {:ok, %{"status" => "not_found"}}

      {:error, {:already_started, _}} ->
        {:ok, %{"status" => "running"}}
    end
  end

  def apply(effect, data) do
    {:error, %{"error" => "no_such_effect", "effect" => effect, "data" => data}}
  end
end
