defmodule Consigliere.Blockchain.RpcClient do
  @moduledoc """
  JSON-RPC client for communicating with the BSV node (bitcoind).

  Provides methods for getblock, getrawtransaction, getblockcount,
  and sendrawtransaction. Uses Req for HTTP POST with basic auth.

  TODO: Implement actual RPC calls in Phase 2.
  """

  use GenServer

  ## ── Client API ──

  @doc """
  Starts the RPC client GenServer. Reads BSV node config from app env.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## ── Server Callbacks ──

  @impl true
  def init(_opts) do
    config = Application.get_env(:consigliere, :bsv_node, [])
    state = %{
      rpc_url: Keyword.get(config, :rpc_url, "http://localhost:18332"),
      rpc_user: Keyword.get(config, :rpc_user),
      rpc_password: Keyword.get(config, :rpc_password)
    }
    {:ok, state}
  end

  @impl true
  def handle_call(_msg, _from, state) do
    {:reply, {:error, :not_implemented}, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
