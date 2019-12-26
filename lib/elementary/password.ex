defmodule Elementary.Password do
  @moduledoc false
  use Elementary.Effect, name: :password

  def handle_call(%{"verify" => clear, "with" => hash}) do
    case Argon2.verify_pass(clear, hash) do
      true ->
        {:ok, %{"status" => "ok"}}

      false ->
        {:ok, %{"status" => "error"}}
    end
  end

  def handle_call(%{"hash" => clear}) do
    {:ok, %{"status" => "ok", "hash" => Argon2.hash_pwd_salt(clear)}}
  end
end
