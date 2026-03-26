defmodule Consigliere.Workers.ChainTipVerifier do
  @moduledoc """
  Periodically verifies chain tip consistency by comparing local state
  against the BSV node. Detects reorgs and triggers rollback if needed.

  TODO: Implement periodic tip verification in Phase 6.
  """

  use GenServer

  @doc """
  Starts the ChainTipVerifier worker.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # TODO: Schedule periodic verification via Process.send_after/3
    {:ok, %{}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
