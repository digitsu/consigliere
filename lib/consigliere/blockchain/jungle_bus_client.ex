defmodule Consigliere.Blockchain.JungleBusClient do
  @moduledoc """
  WebSocket client for JungleBus — an alternative mempool monitor and
  historical transaction source. Enabled via JUNGLE_BUS_ENABLED env var.

  TODO: Implement WebSocket connection and message handling in Phase 7.
  """

  use GenServer

  ## ── Client API ──

  @doc """
  Starts the JungleBus client GenServer. Only connects if enabled in config.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## ── Server Callbacks ──

  @impl true
  def init(_opts) do
    config = Application.get_env(:consigliere, :jungle_bus, [])
    state = %{
      enabled: Keyword.get(config, :enabled, false),
      url: Keyword.get(config, :url),
      connected: false
    }
    {:ok, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
