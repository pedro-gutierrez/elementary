defmodule Elementary.Logger do
  use GenServer

  alias Elementary.{Index, Stores.Store}

  def log(%{"kind" => _, "name" => _} = data) do
    data = Map.put(data, "time", DateTime.utc_now())
    GenServer.cast(__MODULE__, {:write, data})
  end

  def query(%{"spec" => %{"store" => store}}, q) do
    query =
      q
      |> maybe_timerange_query()
      |> maybe_status_code_query()

    store = Index.spec!("store", store)

    Store.find_all(store, "log", query,
      log: :disable,
      sort: %{"time" => "desc", "$natural" => "desc"}
    )
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, host} = :inet.gethostname()
    %{"spec" => %{"debug" => debug, "store" => store}} = Index.spec!("logger", "default")
    debug_fn = Elementary.Kit.debug_fn(debug)
    {:ok, {"#{host}", store, debug_fn}}
  end

  def handle_cast({:write, data}, {host, store, debug} = state) do
    store = Index.spec!("store", store)

    %{"host" => host, "level" => "info"}
    |> Map.merge(data)
    |> write_log(store)
    |> debug.()

    {:noreply, state}
  end

  defp write_log(%{kind: "app", name: "logs"}, _), do: :ok
  defp write_log(%{kind: "app", name: "index"}, _), do: :ok

  defp write_log(data, store) do
    Store.insert(store, "log", data, log: :disable)
    data
  end

  defp maybe_timerange_query(%{"from" => from, "to" => to} = q) do
    with {:ok, from, _} <- DateTime.from_iso8601(from),
         {:ok, to, _} <- DateTime.from_iso8601(to) do
      q
      |> Map.drop(["from", "to"])
      |> Map.put("time", %{
        "$gte" => from,
        "$lt" => to
      })
    else
      _ ->
        q
    end
  end

  defp maybe_timerange_query(%{"from" => from} = q) do
    case DateTime.from_iso8601(from) do
      {:ok, from, _} ->
        q
        |> Map.drop(["from"])
        |> Map.put("time", %{
          "$gte" => from
        })

      _ ->
        q
    end
  end

  defp maybe_timerange_query(q), do: q

  defp maybe_status_code_query(%{"status" => code} = q) do
    case Integer.parse(code) do
      {code, ""} ->
        Map.put(q, "status", code)

      _ ->
        q
    end
  end

  defp maybe_status_code_query(q), do: q
end
