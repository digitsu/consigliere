defmodule ConsigliereWeb.WalletChannelTest do
  use ConsigliereWeb.ChannelCase, async: true

  describe "join" do
    test "joins wallet:lobby successfully" do
      {:ok, _, socket} =
        ConsigliereWeb.UserSocket
        |> socket("user_id", %{})
        |> subscribe_and_join(ConsigliereWeb.WalletChannel, "wallet:lobby")

      assert socket.topic == "wallet:lobby"
    end

    test "joins wallet:{address} successfully" do
      {:ok, _, socket} =
        ConsigliereWeb.UserSocket
        |> socket("user_id", %{})
        |> subscribe_and_join(ConsigliereWeb.WalletChannel, "wallet:1ABC123")

      assert socket.topic == "wallet:1ABC123"
    end
  end

  describe "handle_in" do
    setup do
      {:ok, _, socket} =
        ConsigliereWeb.UserSocket
        |> socket("user_id", %{})
        |> subscribe_and_join(ConsigliereWeb.WalletChannel, "wallet:lobby")

      %{socket: socket}
    end

    test "subscribe replies ok", %{socket: socket} do
      ref = push(socket, "subscribe", %{"address" => "1TestAddr"})
      assert_reply ref, :ok, %{status: "subscribed"}
    end

    test "unsubscribe replies ok", %{socket: socket} do
      ref = push(socket, "unsubscribe", %{"address" => "1TestAddr"})
      assert_reply ref, :ok, %{status: "unsubscribed"}
    end

    test "get_balance replies ok", %{socket: socket} do
      ref = push(socket, "get_balance", %{})
      assert_reply ref, :ok, %{balances: []}
    end

    test "get_history replies ok", %{socket: socket} do
      ref = push(socket, "get_history", %{})
      assert_reply ref, :ok, %{history: []}
    end

    test "get_utxo_set replies ok", %{socket: socket} do
      ref = push(socket, "get_utxo_set", %{})
      assert_reply ref, :ok, %{utxos: []}
    end

    test "get_transactions replies ok", %{socket: socket} do
      ref = push(socket, "get_transactions", %{})
      assert_reply ref, :ok, %{transactions: []}
    end

    test "broadcast replies ok", %{socket: socket} do
      ref = push(socket, "broadcast", %{"hex" => "0100000001..."})
      assert_reply ref, :ok, %{status: "not_implemented"}
    end
  end
end
