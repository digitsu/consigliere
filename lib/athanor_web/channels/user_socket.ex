defmodule AthanorWeb.UserSocket do
  @moduledoc """
  Socket handler for WebSocket connections at /ws/athanor.

  Routes "wallet:*" topics to the WalletChannel for real-time
  transaction and balance notifications.
  """

  use Phoenix.Socket

  channel "wallet:*", AthanorWeb.WalletChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
