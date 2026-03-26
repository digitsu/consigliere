defmodule Consigliere.Workers.MissingTxSyncer do
  @moduledoc """
  Backfills missing transactions by querying JungleBus or WhatsOnChain.

  Handles gaps in the local index caused by downtime or missed ZMQ messages.

  TODO: Implement backfill logic in Phase 6.
  """

  use GenServer

  @doc """
  Starts the MissingTxSyncer worker.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
