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
  Launch a new app, with the given id. If the app
  is already running, simply return its pid
  """
  def launch(app, id) do
    case DynamicSupervisor.start_child(__MODULE__, %{
           id: "#{app}#{id}",
           start: {app, :start_link, [self(), id]},
           type: :worker,
           restart: :transient,
           shutdown: 1000
         }) do
      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:ok, pid} ->
        {:ok, pid}

      other ->
        other
    end
  end

  @doc """
  Launch a new app, with the given id. If the app
  is already running, raise an error
  """
  def launch!(app, id) do
    {:ok, _} =
      DynamicSupervisor.start_child(__MODULE__, %{
        id: "#{app}#{id}",
        start: {app, :start_link, [self(), id]},
        type: :worker,
        restart: :transient,
        shutdown: 1000
      })
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

  @doc """
  Return the number of running apps
  """
  def count() do
    %{active: active} = Supervisor.count_children(__MODULE__)
    active
  end
end
