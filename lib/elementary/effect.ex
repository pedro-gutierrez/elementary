defmodule Elementary.Effect do
  @moduledoc false

  alias Elementary.Kit

  def apply("uuid", _) do
    {:ok, %{"uuid" => UUID.uuid4()}}
  end

  def apply("file", %{"named" => name}) do
    case Elementary.Encoder.encode(name) do
      {:ok, file} ->
        {:ok, Map.put(file, "status", "ok")}

      {:error, e} ->
        {:ok, %{"status" => "error", "reason" => e}}
    end
  end

  def apply("password", %{"verify" => clear, "with" => hash}) do
    try do
      Argon2.verify_pass(clear, hash)
    rescue
      _ ->
        false
    end
    |> case do
      true ->
        {:ok, %{"status" => "ok"}}

      false ->
        {:ok, %{"status" => "error"}}
    end
  end

  def apply("password", %{
        "hash" => clear,
        "options" => %{"time" => t, "memory" => m, "length" => l}
      }) do
    {:ok,
     %{
       "status" => "ok",
       "hash" => Argon2.hash_pwd_salt(clear, t_cost: t, m_cost: m, hashlen: l)
     }}
  end

  def apply("store", %{"store" => store, "ping" => _} = spec) do
    {:ok, store} = Elementary.Index.get("store", store)

    case store.ping() do
      :ok -> "ok"
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"store" => store, "insert" => doc, "into" => col} = spec)
      when is_map(doc) do
    {:ok, store} = Elementary.Index.get("store", store)

    case store.insert(col, doc) do
      :ok -> "created"
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"store" => store, "where" => query, "update" => doc, "into" => col} = spec)
      when is_map(doc) do
    {:ok, store} = Elementary.Index.get("store", store)

    query = Kit.with_mongo_id(query)

    case store.update(col, query, doc) do
      :ok -> "updated"
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"store" => store, "delete" => query, "from" => col} = spec) do
    {:ok, store} = Elementary.Index.get("store", store)

    query = Kit.with_mongo_id(query)

    case store.delete(col, query) do
      :ok -> "deleted"
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"store" => store, "from" => col, "fetch" => query} = spec) do
    {:ok, store} = Elementary.Index.get("store", store)

    query = Kit.with_mongo_id(query)

    case store.find_one(col, query) do
      {:ok, item} -> item
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"store" => store, "aggregate" => pipeline, "from" => col} = spec) do
    {:ok, store} = Elementary.Index.get("store", store)

    case store.aggregate(col, pipeline) do
      {:ok, items} -> items
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"store" => store, "from" => col} = spec) do
    {:ok, store} = Elementary.Index.get("store", store)

    case store.find_all(col, spec["find"] || %{}) do
      {:ok, items} -> items
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"empty" => %{}, "store" => store} = spec) do
    {:ok, store} = Elementary.Index.get("store", store)

    case store.empty() do
      :ok -> "empty"
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"reset" => %{}, "store" => store} = spec) do
    {:ok, store} = Elementary.Index.get("store", store)

    case store.empty() do
      :ok -> "reset"
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
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

  def apply("app", %{"app" => app}) do
    with {:ok, app} <- Elementary.Index.get("app", app),
         {:ok, settings} <- app.settings do
      {:ok,
       app.spec
       |> Map.put("settings", settings)
       |> Map.drop(["modules"])}
    end
  end

  def apply(effect, data) do
    {:error, %{"error" => "no_such_effect", "effect" => effect, "data" => data}}
  end

  defp effect_result(res, spec) do
    {:ok, maybe_alias(spec["as"], res)}
  end

  defp maybe_alias(nil, res), do: res
  defp maybe_alias(as, res), do: %{as => res}
end
