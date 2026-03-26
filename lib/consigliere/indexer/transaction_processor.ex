defmodule Consigliere.Indexer.TransactionProcessor do
  @moduledoc """
  Core indexing pipeline: receives raw transactions that passed the filter,
  parses them via bsv_sdk_elixir, classifies outputs (P2PKH/STAS/DSTAS),
  updates the UTXO set, and publishes events via PubSub.

  Pipeline: filter → parse → classify → store → notify

  TODO: Implement full pipeline in Phase 3.
  """

  use GenServer

  ## ── Client API ──

  @doc """
  Starts the TransactionProcessor GenServer.
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
