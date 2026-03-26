defmodule Consigliere.Workers.StasObserver do
  @moduledoc """
  Watches for STAS token attribute changes (e.g. metadata updates,
  redemption events) and updates local state accordingly.

  TODO: Implement STAS attribute observation in Phase 6.
  """

  use GenServer

  @doc """
  Starts the StasObserver worker.
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
