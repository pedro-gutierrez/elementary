defmodule Elementary.Exchanges do
  @moduledoc """
  A gateway to a crypto exchange
  """

  use Supervisor
  alias Elementary.Exchanges.Fake

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  def init(_) do
    [Fake]
    |> Supervisor.init(strategy: :one_for_one)
  end

  defmodule Fake do
    @moduledoc false

    use GenServer
    require Logger

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    def init(_) do
      {:ok, %{}}
    end

    def buy(order) do
      GenServer.call(__MODULE__, {:buy, order})
    end

    def handle_call({:buy, order}, _, state) do
      Logger.debug("buy #{inspect(order)}")
      {:reply, {:ok, order}, state}
    end
  end
end
