defmodule Elementary.Kit do
  @moduledoc false

  @doc """
  Returns the home folder, where all yamls are
  """
  def home(), do: System.get_env("ELEMENTARY_HOME", "/elementary")

  @doc """
  Returns the assets folder
  """
  def assets(), do: System.get_env("ELEMENTARY_ASSETS", Path.join(home(), "assets"))

  @doc """
  Parse the given filename as yaml
  """
  def read_yaml(path) do
    YamlElixir.read_from_file(path)
  end

  @doc """
  Start watching the home folder for file changes
  """
  def watch() do
    {:ok, pid} = FileSystem.start_link(dirs: [home()])
    FileSystem.subscribe(pid)
    {:ok, pid}
  end

  def behaviours(mod) do
    Enum.reduce(mod.module_info(:attributes), [], fn
      {:behaviour, [b]}, all ->
        [b | all]

      _, all ->
        all
    end)
  end

  def defines_child_spec?(mod) do
    Kernel.function_exported?(mod, :child_spec, 1)
  end

  def log(kind, name, data) do
    IO.inspect(%{
      kind: kind,
      name: name,
      data: data,
      time: DateTime.utc_now(),
      node: Node.self()
    })
  end

  def module_name(parts) do
    Module.concat([
      camelize(parts)
    ])
  end

  def camelize(parts) do
    parts
    |> Enum.map(&capitalize(&1))
    |> Enum.join("")
    |> Macro.camelize()
  end

  defp capitalize(atom) when is_atom(atom) do
    atom |> Atom.to_string() |> capitalize()
  end

  defp capitalize(str) when is_binary(str) do
    String.capitalize(str)
  end

  def duration(since) do
    ceil(now() - since)
  end

  def duration(since, :millisecond) do
    ceil(duration(since) / 1000)
  end

  def now(unit \\ :microsecond) do
    System.system_time(unit)
  end

  def millis() do
    now(:millisecond)
  end

  def millis_since(start) do
    millis() - start
  end

  def datetime_from_mongo_id(id) do
    {part, _} = String.split_at(id, 8)
    {ts, ""} = Integer.parse(part, 16)
    {:ok, dt} = DateTime.from_unix(ts)
    dt
  end

  def mongo_url(%{
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

    "#{scheme}://#{username}:#{password}@#{host}/#{db}?#{params}"
  end

  def mongo_url(%{
        "db" => db
      }) do
    "mongodb://localhost/#{db}"
  end

  def mongo_url(url) when is_binary(url) do
    url
  end

  def with_mongo_id(%{"id" => id} = doc) do
    doc
    |> Map.put("_id", id)
    |> Map.drop(["id"])
  end

  def with_mongo_id(doc), do: doc

  def without_mongo_id(%{"_id" => id} = doc) do
    doc
    |> Map.put("id", encode_mongo_id(id))
    |> Map.drop(["_id"])
  end

  def without_mongo_id(doc), do: doc

  defp encode_mongo_id(%BSON.ObjectId{} = id) do
    BSON.ObjectId.encode!(id)
  end

  defp encode_mongo_id(id), do: id

  def stream_from_data(data) when is_binary(data) do
    {:ok, pid} = StringIO.open(data)
    IO.binstream(pid, 256)
  end

  def procs(limit \\ 5) do
    :erlang.processes()
    |> Enum.reject(fn pid ->
      pid == self()
    end)
    |> Enum.map(fn pid ->
      info =
        :erlang.process_info(pid, [
          :memory,
          :registered_name,
          :current_function,
          :initial_call,
          :dictionary
        ])

      %{
        memory: info[:memory],
        name: info[:registered_name],
        current_fun: info[:current_function],
        initial_call: info[:initial_call],
        dictionary: info[:dictionary],
        pid: pid
      }
    end)
    |> Enum.sort(&(&1[:memory] >= &2[:memory]))
    |> Enum.take(limit)
  end

  def gc(limit \\ 5) do
    procs(limit)
    |> Enum.map(fn info ->
      info[:pid]
    end)
    |> Enum.each(fn pid ->
      :erlang.garbage_collect(pid)
    end)
  end
end
