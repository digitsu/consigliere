defmodule Consigliere.Indexer.BlockProcessor do
  @moduledoc """
  Processes blocks sequentially, confirms UTXOs, and detects chain reorgs.

  When a new block hash arrives via ZMQ, this module fetches block data,
  processes each transaction, updates confirmation status, and records
  the block in block_process_contexts. Handles reorg by rolling back
  to the fork point.

  TODO: Implement block ingestion and reorg detection in Phase 3.
  """

  use GenServer

  ## ── Client API ──

  @doc """
  Starts the BlockProcessor GenServer.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## ── Server Callbacks ──

  @impl true
  def init(_opts) do
    {:ok, %{}}
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
