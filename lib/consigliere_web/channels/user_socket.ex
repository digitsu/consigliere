defmodule ConsigliereWeb.UserSocket do
  @moduledoc """
  Socket handler for WebSocket connections at /ws/consigliere.

  Routes "wallet:*" topics to the WalletChannel for real-time
  transaction and balance notifications.
  """

  use Phoenix.Socket

  channel "wallet:*", ConsigliereWeb.WalletChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
