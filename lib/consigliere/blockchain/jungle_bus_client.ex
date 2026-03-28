defmodule Consigliere.Blockchain.JungleBusClient do
  @moduledoc """
  WebSocket client for JungleBus — an alternative mempool monitor and
  historical transaction source. Enabled via JUNGLE_BUS_ENABLED env var.

  When enabled, connects to JungleBus and subscribes to transaction events,
  forwarding matched transactions to the indexing pipeline.
  """

  use GenServer
  require Logger

  alias Consigliere.Indexer.TransactionFilter

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    config = Application.get_env(:consigliere, :jungle_bus, [])

    state = %{
      enabled: Keyword.get(config, :enabled, false),
      url: Keyword.get(config, :url),
      connected: false,
      ws_pid: nil
    }

    if state.enabled and state.url do
      send(self(), :connect)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, %{enabled: false} = state), do: {:noreply, state}

  def handle_info(:connect, %{url: nil} = state), do: {:noreply, state}

  def handle_info(:connect, state) do
    Logger.info("JungleBusClient: connecting to #{state.url}")

    # JungleBus WS not yet implemented — retry loop until configured
    Logger.warning("JungleBusClient: WebSocket client not yet implemented, retrying in 30s")
    Process.send_after(self(), :connect, 30_000)
    {:noreply, %{state | connected: false}}
  end

  def handle_info({:junglebus_tx, raw_tx_binary}, state) do
    # Forward to the transaction filter pipeline
    TransactionFilter.process_raw_tx(raw_tx_binary)
    {:noreply, state}
  end

  def handle_info({:junglebus_disconnected, _reason}, state) do
    Logger.warning("JungleBusClient: disconnected, reconnecting in 5s")
    Process.send_after(self(), :connect, 5_000)
    {:noreply, %{state | connected: false, ws_pid: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## ── Private ──

  # Called when JungleBus WS is implemented — currently a placeholder
  @doc false
  def connect_ws(url) do
    # JungleBus WebSocket connection
    # This would use :gun or mint_web_socket in production.
    # The JungleBus API sends transaction events as binary frames.
    #
    # Implementation steps:
    # 1. :gun.open(host, port, %{protocols: [:http], transport: :tls})
    # 2. :gun.ws_upgrade(conn, path)
    # 3. Subscribe to address/token filters via JungleBus protocol
    # 4. Receive tx events and forward to TransactionFilter
    if url do
      {:error, :not_yet_implemented}
    else
      {:error, :not_configured}
    end
  end
end
