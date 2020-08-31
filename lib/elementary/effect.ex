defmodule Elementary.Effect do
  @moduledoc false

  require Logger
  alias Elementary.{Kit, App, Index, Stores.Store, Services.Service, Slack}

  def apply("uuid", _) do
    {:ok, %{"uuid" => UUID.uuid4()}}
  end

  def apply("slack", %{"channel" => channel, "text" => text, "data" => data}) do
    Slack.notify(channel, text, data)
  end

  def apply("slack", %{"channel" => channel, "text" => text}) do
    Slack.notify(channel, text)
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

  def apply("stream", %{"write" => data, "to" => stream} = spec) do
    Elementary.Streams.Stream.write(stream, data)
    |> effect_result(spec)
  end

  def apply("cluster", %{"info" => _} = spec) do
    Elementary.Cluster.info()
    |> effect_result(spec)
  end

  def apply("store", %{"store" => store, "ping" => _} = spec) do
    with {:ok, store} <- Index.spec("store", store) do
      case Store.ping(store) do
        :ok -> "ok"
        {:error, e} -> "#{e}"
      end
    end
    |> effect_result(spec)
  end

  def apply("store", %{"store" => store, "insert" => doc, "into" => col} = spec)
      when is_map(doc) do
    store = Index.spec!("store", store)

    case Store.insert(store, col, doc) do
      :ok -> "created"
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"store" => store, "from" => col, "fetch" => query} = spec) do
    store = Index.spec!("store", store)

    query = Kit.with_mongo_id(query)

    case Store.find_one(store, col, query, remove: spec["delete"] || false) do
      {:ok, item} -> item
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"store" => store, "where" => query, "update" => doc, "into" => col} = spec)
      when is_map(doc) do
    store = Index.spec!("store", store)
    query = Kit.with_mongo_id(query)

    case Store.update(store, col, query, doc) do
      {:ok, updated} -> updated
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"store" => store, "where" => query, "ensure" => doc, "into" => col} = spec)
      when is_map(doc) do
    store = Index.spec!("store", store)
    query = Kit.with_mongo_id(query)

    case Store.update(store, col, query, doc, true) do
      {:ok, updated} -> updated
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"store" => store, "delete" => query, "from" => col} = spec) do
    store = Index.spec!("store", store)

    query = Kit.with_mongo_id(query)

    case Store.delete(store, col, query) do
      {:ok, deleted} -> deleted
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"store" => store, "aggregate" => pipeline, "from" => col} = spec) do
    store = Index.spec!("store", store)

    case Store.aggregate(store, col, pipeline) do
      {:ok, items} -> items
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"store" => store, "from" => col} = spec) do
    store = Index.spec!("store", store)

    opts = []

    opts =
      case spec["sort"] do
        nil ->
          opts

        sort ->
          Keyword.put(opts, :sort, sort)
      end

    case Store.find_all(store, col, spec["find"] || %{}, opts) do
      {:ok, items} -> items
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"empty" => %{}, "store" => store} = spec) do
    store = Index.spec!("store", store)

    case Store.empty(store) do
      :ok -> "empty"
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("store", %{"reset" => %{}, "store" => store} = spec) do
    store = Index.spec!("store", store)

    case Store.reset(store) do
      :ok -> "reset"
      {:error, e} -> "#{e}"
    end
    |> effect_result(spec)
  end

  def apply("http", spec) do
    [
      debug: spec["debug"],
      method: spec["method"] || "get",
      url: spec["url"],
      body: spec["body"],
      headers: spec["headers"],
      query: spec["query"]
    ]
    |> Elementary.Http.Client.run()
    |> effect_result(spec)
  end

  def apply("service", %{"app" => app, "params" => data} = spec) do
    app
    |> Service.run("caller", data)
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

  def apply("spec", %{"app" => app}) do
    with {:ok, spec} <- Index.spec("app", app),
         {:ok, settings} <- App.settings(spec) do
      %{"spec" => spec0} = spec

      spec0 =
        spec0
        |> Map.put("settings", settings)
        |> Map.drop(["modules"])

      {:ok, spec0}
    end
  end

  def apply("jwt", %{"decode" => token} = spec) do
    with [_header, claims, _signature] <- String.split(token, "."),
         {:ok, data} <- Base.url_decode64(claims, padding: false),
         {:ok, data} <- Jason.decode(data) do
      %{"claims" => data}
    else
      _ ->
        "invalid"
    end
    |> effect_result(spec)
  end

  def apply("facebook", %{"resolve" => id} = spec) do
    id
    |> Elementary.Facebook.resolve_event()
    |> effect_result(spec)
  end

  def apply(effect, data) do
    {:error, %{"error" => "no_such_effect", "effect" => effect, "data" => data}}
  end

  defp effect_result({_, data}, spec) when is_atom(data) do
    effect_result("#{data}", spec)
  end

  defp effect_result({_, data}, spec) do
    effect_result(data, spec)
  end

  defp effect_result(res, spec) do
    res = maybe_alias(spec["as"], res)

    if spec["debug"] do
      Logger.info(
        "#{
          inspect(
            effect: [
              spec: spec,
              result: res
            ]
          )
        }"
      )
    end

    {:ok, res}
  end

  defp maybe_alias(nil, res), do: res
  defp maybe_alias(as, res), do: %{as => res}
end
