defmodule Elementary.Kit do
  @moduledoc false

  @doc """
  Returns the home folder, where all yamls are
  """
  def home(), do: System.get_env("ELEMENTARY_HOME", "/elementary")

  @doc """
  Returns the assets folder
  """
  def assets(), do: System.get_env("ELEMENTARY_ASSETS", "/tmp")

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

  def now() do
    DateTime.to_unix(DateTime.utc_now(), :microsecond)
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
end
