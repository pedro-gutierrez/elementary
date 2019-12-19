defmodule Elementary.Index do
  defmodule Store do
    def get(_), do: {:error, :not_found}
  end

  defmodule Entity do
    def get(_), do: {:error, :not_found}
    def all(), do: []
  end

  defmodule EntityView do
    def get(_), do: {:error, :not_found}
    def all(), do: []
  end
end
