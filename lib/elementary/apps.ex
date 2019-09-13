defmodule Elementary.Apps do
  @moduledoc """
  A supervisor for all apps
  """

  use DynamicSupervisor

  @doc """
  Start this supervisor and add it to the supervision
  tree
  """
  def start_link(args) do
    DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  Define a new dynamic supervisor, so that we
  can add new app processes later on
  """
  @impl true
  def init(args) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: args
    )
  end

  @doc """
  Launch a new app, with the given initial data
  """
  def launch(app) do
    DynamicSupervisor.start_child(__MODULE__, %{
      id: app,
      start: {app, :start_link, [self()]},
      type: :worker,
      restart: :transient,
      shutdown: 1000
    })
  end
end
