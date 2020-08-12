defmodule Elementary.Cluster do
  @moduledoc false

  use Supervisor
  alias Elementary.Encoder

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def partitions(%{"spec" => spec}) do
    {:ok, %{"size" => size, "prefix" => prefix}} = Encoder.encode(spec)
    size = String.to_integer(size)
    case size do
      size when size > 1 ->
        {:ok, host} = :inet.gethostname()
        partition =
          "#{host}"
          |> String.split(".")
          |> List.first()
          |> String.replace_prefix(prefix, "")
          |> String.to_integer()

        %{size: size, partition: partition}

      1 ->
        %{size: 1, partition: 1}
    end
  end

  def init(_) do
    case Elementary.Index.spec("cluster", "default") do
      {:ok, %{"spec" => %{"topology" => "hosts"}}} ->
        topologies = [
          default: [
            strategy: Cluster.Strategy.ErlangHosts
          ]
        ]

        [
          {Cluster.Supervisor, [topologies, [name: Elementary.ClusterSupervisor]]}
        ]

      {:ok, _} ->
        []
    end
    |> Supervisor.init(strategy: :one_for_one)
  end
end
