defmodule Elementary.Effect do
  @moduledoc false

  alias Elementary.Kit

  def apply("uuid", _) do
    {:ok, %{"uuid" => UUID.uuid4()}}
  end

  def apply("asset", %{"named" => name}) do
    path = "#{Kit.assets()}/#{name}"

    with {:ok, %{type: type, size: size, atime: modified, ctime: created}} <- File.lstat(path),
         {:ok, data} <- File.read(path) do
      {:ok,
       %{
         "status" => "ok",
         "data" => data,
         "size" => size,
         "type" => type,
         "modified" => modified,
         "created" => created
       }}
    else
      {:error, :enoent} ->
        {:ok, %{"status" => "error", "reason" => "not_found"}}
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

       {:error, e} ->
         %{"status" => e}
     end}
  end

  def apply("store", %{"store" => store, "from" => col, "fetch" => query, "as" => as}) do
    {:ok, store} = Elementary.Index.get("store", store)

    {:ok,
     case store.find_one(col, query) do
       {:ok, item} ->
         %{as => item}

       {:error, e} when is_atom(e) ->
         %{"status" => Atom.to_string(e)}
     end}
  end

  def apply("store", %{"store" => store, "from" => col}) do
    {:ok, store} = Elementary.Index.get("store", store)

    {:ok,
     case store.find_all(col, %{}) do
       {:ok, items} ->
         %{"items" => items}

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

  def apply(effect, data) do
    {:error, %{"error" => "no_such_effect", "effect" => effect, "data" => data}}
  end
end
