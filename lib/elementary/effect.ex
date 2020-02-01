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
end
