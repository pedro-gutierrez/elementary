defmodule Elementary.Cluster do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    case Elementary.Index.spec("cluster", "default") do
      :not_found -> []

      {:ok, %{"topology" => "hosts"}} ->
        topologies = [
          default: [
            strategy: Cluster.Strategy.ErlangHosts
          ]
        ]

        [
          {Cluster.Supervisor, [topologies, [name: Elementary.ClusterSupervisor]]}
        ]
    end
    |> Supervisor.init(strategy: :one_for_one)
  end

end
