defmodule Consigliere.Blockchain.ZmqListener do
  @moduledoc """
  ZMQ subscriber that listens for raw transaction and block hash notifications
  from the BSV node. Uses the chumak library (pure Erlang ZMQ).

  Subscribes to topics: rawtx, hashblock, removedfrommempool, discardedfromempool.
  On receipt, forwards messages to the TransactionFilter / BlockProcessor.

  TODO: Implement ZMQ subscription and message dispatch in Phase 2.
  """

  use GenServer

  ## ── Client API ──

  @doc """
  Starts the ZMQ listener GenServer. Reads ZMQ endpoints from app config.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## ── Server Callbacks ──

  @impl true
  def init(_opts) do
    zmq_config = Application.get_env(:consigliere, :zmq, [])
    state = %{
      raw_tx_endpoint: Keyword.get(zmq_config, :raw_tx),
      hash_block_endpoint: Keyword.get(zmq_config, :hash_block),
      connected: false
    }
    # TODO: Connect to ZMQ endpoints via chumak in Phase 2
    {:ok, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
