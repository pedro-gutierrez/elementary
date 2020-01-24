defmodule Elementary.Asset do
  @moduledoc false

  use Elementary.Effect, name: :asset
  alias Elementary.Kit

  def handle_call(%{"named" => name}) do
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
end
