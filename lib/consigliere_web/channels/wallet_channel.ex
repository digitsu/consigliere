defmodule ConsigliereWeb.WalletChannel do
  @moduledoc """
  Phoenix Channel handling the "wallet:*" topic for real-time events.

  Supports per-address topics ("wallet:{address}") and a lobby ("wallet:lobby").

  ## Client → Server events (PRD §6.2):
    - `subscribe` — subscribe to tx stream for an address
    - `unsubscribe` — unsubscribe
    - `get_balance` — query balances
    - `get_history` — address history
    - `get_utxo_set` — UTXO set query
    - `get_transactions` — batch tx lookup
    - `broadcast` — broadcast a raw transaction

  ## Server → Client events:
    - `tx_found` — new transaction for subscribed address
    - `tx_deleted` — transaction removed (reorg/eviction)
    - `balance_changed` — balance update notification

  TODO: Implement real event handling in Phase 5.
  """

  use ConsigliereWeb, :channel

  @impl true
  def join("wallet:" <> _subtopic, _payload, socket) do
    {:ok, socket}
  end

  # ── Client → Server handlers ──

  @impl true
  def handle_in("subscribe", %{"address" => _address} = _payload, socket) do
    # TODO: Register subscription in Registry, subscribe to PubSub topic
    {:reply, {:ok, %{status: "subscribed"}}, socket}
  end

  @impl true
  def handle_in("unsubscribe", %{"address" => _address} = _payload, socket) do
    # TODO: Remove subscription from Registry
    {:reply, {:ok, %{status: "unsubscribed"}}, socket}
  end

  @impl true
  def handle_in("get_balance", _payload, socket) do
    # TODO: Delegate to Consigliere.Services.Balance
    {:reply, {:ok, %{balances: []}}, socket}
  end

  @impl true
  def handle_in("get_history", _payload, socket) do
    # TODO: Delegate to Consigliere.Services.AddressHistory
    {:reply, {:ok, %{history: []}}, socket}
  end

  @impl true
  def handle_in("get_utxo_set", _payload, socket) do
    # TODO: Delegate to Consigliere.Indexer.UtxoManager
    {:reply, {:ok, %{utxos: []}}, socket}
  end

  @impl true
  def handle_in("get_transactions", _payload, socket) do
    # TODO: Batch tx lookup from MetaTransaction table
    {:reply, {:ok, %{transactions: []}}, socket}
  end

  @impl true
  def handle_in("broadcast", _payload, socket) do
    # TODO: Delegate to Consigliere.Services.Broadcast
    {:reply, {:ok, %{status: "not_implemented"}}, socket}
  end
end
