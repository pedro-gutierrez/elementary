defmodule Elementary.Index do
  @moduledoc false

  def spec(_, _), do: :not_found
  def get(_, _), do: {:error, :not_implemented}
  def get!(_, _), do: raise("not implemented Elementary.Index.get!/2")
end
