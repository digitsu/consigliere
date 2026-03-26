defmodule Consigliere.Workers.UnconfirmedMonitor do
  @moduledoc """
  Periodically rechecks stale unconfirmed transactions to determine
  if they've been confirmed, dropped from mempool, or replaced.

  TODO: Implement periodic recheck logic in Phase 6.
  """

  use GenServer

  @doc """
  Starts the UnconfirmedMonitor worker.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # TODO: Schedule periodic check via Process.send_after/3
    {:ok, %{}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
