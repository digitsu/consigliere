defmodule Athanor.Blockchain.Supervisor do
  @moduledoc """
  Supervises blockchain interaction processes with :rest_for_one strategy.

  Order matters: Network must start first (config), then RpcClient (needs
  network config), then ZmqListener (needs both). If Network crashes,
  everything downstream restarts.
  """

  use Supervisor

  @doc """
  Starts the blockchain supervisor.
  """
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      Athanor.Blockchain.Network,
      Athanor.Blockchain.RpcClient,
      Athanor.Blockchain.ZmqListener
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
