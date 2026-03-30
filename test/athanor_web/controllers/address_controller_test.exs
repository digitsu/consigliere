defmodule AthanorWeb.AddressControllerTest do
  @moduledoc """
  Tests for the AddressController — balance and UTXO endpoints.
  """

  use AthanorWeb.ConnCase, async: true

  import Athanor.Fixtures

  describe "GET /api/address/:address/balance" do
    test "returns zero balance for address with no UTXOs", %{conn: conn} do
      conn = get(conn, "/api/address/1NoUtxoAddr/balance")
      assert %{"address" => "1NoUtxoAddr", "bsv" => 0, "tokens" => []} = json_response(conn, 200)
    end

    test "returns sum of unspent UTXOs for address", %{conn: conn} do
      address = "1BalanceTestAddr"
      utxo_fixture(%{address: address, satoshis: 50_000})
      utxo_fixture(%{address: address, satoshis: 75_000})

      conn = get(conn, "/api/address/#{address}/balance")

      response = json_response(conn, 200)
      assert response["address"] == address
      assert response["bsv"] in [125_000, "125000"]
    end

    test "excludes spent UTXOs from balance", %{conn: conn} do
      address = "1SpentTestAddr"
      utxo_fixture(%{address: address, satoshis: 100_000})
      utxo_fixture(%{address: address, satoshis: 40_000, is_spent: true})

      conn = get(conn, "/api/address/#{address}/balance")

      response = json_response(conn, 200)
      assert response["bsv"] in [100_000, "100000"]
    end
  end

  describe "GET /api/address/:address/utxos" do
    test "returns empty list for address with no UTXOs", %{conn: conn} do
      conn = get(conn, "/api/address/1EmptyAddr/utxos")
      assert %{"address" => "1EmptyAddr", "utxos" => []} = json_response(conn, 200)
    end

    test "returns only unspent UTXOs", %{conn: conn} do
      address = "1UtxoTestAddr"
      utxo_fixture(%{address: address, satoshis: 10_000})
      utxo_fixture(%{address: address, satoshis: 20_000, is_spent: true})

      conn = get(conn, "/api/address/#{address}/utxos")

      assert %{"address" => ^address, "utxos" => utxos} = json_response(conn, 200)
      assert length(utxos) == 1
      assert hd(utxos)["satoshis"] == 10_000
    end

    test "returns txid as hex string", %{conn: conn} do
      address = "1HexCheckAddr"
      utxo_fixture(%{address: address})

      conn = get(conn, "/api/address/#{address}/utxos")

      assert %{"utxos" => [utxo]} = json_response(conn, 200)
      assert is_binary(utxo["txid"])
      # txid should be 64-char hex (32 bytes encoded)
      assert String.length(utxo["txid"]) == 64
    end
  end
end
