defmodule Elementary.Mount do
  @moduledoc false

  defstruct app: nil, path: nil, protocol: :http

  def parse(mounts) do
    {:ok,
     Enum.flat_map(mounts, fn {app, app_mounts} ->
       Enum.map(app_mounts, fn {protocol, path} ->
         %__MODULE__{
           app: String.to_atom(app),
           protocol: String.to_atom(protocol),
           path: path
         }
       end)
     end)
     |> Enum.reverse()}
  end
end
