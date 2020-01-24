defmodule Elementary.Index do
  defmodule App do
    def get(_), do: {:error, :not_found}
    def all(), do: []
  end

  defmodule Settings do
    def get(_), do: {:error, :not_found}
    def all(), do: []
  end

  defmodule Entity do
    def get(_), do: {:error, :not_found}
    def all(), do: []
  end

  defmodule Store do
    def get(_), do: {:error, :not_found}
    def all(), do: []
  end

  defmodule Effect do
    def get(_), do: {:error, :not_found}
    def all(), do: []
  end
end
