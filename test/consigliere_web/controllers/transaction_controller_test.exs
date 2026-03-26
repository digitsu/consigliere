defmodule ConsigliereWeb.TransactionControllerTest do
  @moduledoc """
  Tests for the TransactionController — show and broadcast endpoints.
  """

  use ConsigliereWeb.ConnCase, async: true

  import Consigliere.Fixtures

  describe "GET /api/transaction/:txid" do
    test "returns transaction when found", %{conn: conn} do
      tx = meta_transaction_fixture()
      txid_hex = Base.encode16(tx.txid, case: :lower)

      conn = get(conn, "/api/transaction/#{txid_hex}")

      assert %{
               "txid" => ^txid_hex,
               "is_confirmed" => false,
               "timestamp" => _
             } = json_response(conn, 200)
    end

    test "returns 404 when transaction not found", %{conn: conn} do
      fake_txid = String.duplicate("ab", 32)

      conn = get(conn, "/api/transaction/#{fake_txid}")

      assert %{"error" => "transaction not found"} = json_response(conn, 404)
    end

    test "returns 400 for invalid hex txid", %{conn: conn} do
      conn = get(conn, "/api/transaction/not_valid_hex!")

      assert %{"error" => "invalid txid hex"} = json_response(conn, 400)
    end
  end

  describe "POST /api/transaction/broadcast" do
    test "creates broadcast record with pending status", %{conn: conn} do
      hex = "0100000001" <> String.duplicate("00", 50)

      conn = post(conn, "/api/transaction/broadcast", %{hex: hex})

      assert %{"txid" => _, "status" => "pending"} = json_response(conn, 201)
    end

    test "returns 422 when hex is missing", %{conn: conn} do
      conn = post(conn, "/api/transaction/broadcast", %{})

      assert %{"error" => "missing required field: hex"} = json_response(conn, 422)
    end
  end
end
