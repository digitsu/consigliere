defmodule Consigliere.Blockchain.Network do
  @moduledoc """
  Holds network configuration (mainnet/testnet) and provides accessor functions.

  Started first in the Blockchain.Supervisor (:rest_for_one) so that
  RpcClient and ZmqListener can read network config on init.
  """

  use GenServer

  ## ── Client API ──

  @doc """
  Starts the Network GenServer, reading :network from app config.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the current network name (e.g. "mainnet" or "testnet").
  """
  def current do
    GenServer.call(__MODULE__, :current)
  end

  ## ── Server Callbacks ──

  @impl true
  def init(_opts) do
    network = Application.get_env(:consigliere, :network, "testnet")
    {:ok, %{network: network}}
  end

  @impl true
  def handle_call(:current, _from, state) do
    {:reply, state.network, state}
  end
end
