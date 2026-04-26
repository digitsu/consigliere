defmodule AthanorWeb.AdminControllerTest do
  use AthanorWeb.ConnCase, async: true

  alias Athanor.Repo
  alias Athanor.Schema.{WatchingAddress, WatchingToken}

  describe "POST /api/admin/manage/address" do
    test "creates a watched address", %{conn: conn} do
      conn = post(conn, "/api/admin/manage/address", %{address: "1TestAddr", name: "My Wallet"})

      assert %{"id" => _, "address" => "1TestAddr", "name" => "My Wallet"} =
               json_response(conn, 201)
    end

    test "returns 422 without address", %{conn: conn} do
      conn = post(conn, "/api/admin/manage/address", %{name: "No Address"})
      assert %{"errors" => %{"address" => _}} = json_response(conn, 422)
    end

    test "returns 422 for duplicate address", %{conn: conn} do
      Repo.insert!(%WatchingAddress{address: "1DupAddr"})
      conn = post(conn, "/api/admin/manage/address", %{address: "1DupAddr"})
      assert %{"errors" => %{"address" => _}} = json_response(conn, 422)
    end
  end

  describe "GET /api/admin/manage/addresses" do
    test "lists all watched addresses", %{conn: conn} do
      Repo.insert!(%WatchingAddress{address: "1Addr1"})
      Repo.insert!(%WatchingAddress{address: "1Addr2"})

      conn = get(conn, "/api/admin/manage/addresses")
      assert %{"addresses" => addresses} = json_response(conn, 200)
      assert length(addresses) == 2
    end

    test "returns empty list when none exist", %{conn: conn} do
      conn = get(conn, "/api/admin/manage/addresses")
      assert %{"addresses" => []} = json_response(conn, 200)
    end
  end

  describe "POST /api/admin/manage/stas-token" do
    test "creates a watched token", %{conn: conn} do
      conn = post(conn, "/api/admin/manage/stas-token", %{token_id: "tok_abc", symbol: "ABC"})
      assert %{"id" => _, "token_id" => "tok_abc", "symbol" => "ABC"} = json_response(conn, 201)
    end

    test "returns 422 without token_id", %{conn: conn} do
      conn = post(conn, "/api/admin/manage/stas-token", %{symbol: "TST"})
      assert %{"errors" => %{"token_id" => _}} = json_response(conn, 422)
    end

    test "returns 422 for duplicate token_id", %{conn: conn} do
      Repo.insert!(%WatchingToken{token_id: "dup_tok"})
      conn = post(conn, "/api/admin/manage/stas-token", %{token_id: "dup_tok"})
      assert %{"errors" => %{"token_id" => _}} = json_response(conn, 422)
    end
  end

  describe "GET /api/admin/manage/stas-tokens" do
    test "lists all watched tokens", %{conn: conn} do
      Repo.insert!(%WatchingToken{token_id: "tok1"})
      Repo.insert!(%WatchingToken{token_id: "tok2", symbol: "T2"})

      conn = get(conn, "/api/admin/manage/stas-tokens")
      assert %{"tokens" => tokens} = json_response(conn, 200)
      assert length(tokens) == 2
    end

    test "exposes freeze_auth and confiscate_auth as hex strings", %{conn: conn} do
      freeze_pkh = :binary.copy(<<0x11>>, 20)
      conf_pkh = :binary.copy(<<0x22>>, 20)

      Repo.insert!(%WatchingToken{
        token_id: "proto_xy",
        freeze_auth: freeze_pkh,
        confiscate_auth: conf_pkh
      })

      conn = get(conn, "/api/admin/manage/stas-tokens")
      assert %{"tokens" => [t]} = json_response(conn, 200)

      assert t["token_id"] == "proto_xy"
      assert t["freeze_auth"] == Base.encode16(freeze_pkh, case: :lower)
      assert t["confiscate_auth"] == Base.encode16(conf_pkh, case: :lower)
    end
  end

  describe "GET /api/admin/blockchain/sync-status" do
    test "returns sync status", %{conn: conn} do
      conn = get(conn, "/api/admin/blockchain/sync-status")
      assert %{"last_block_height" => 0, "is_synced" => false} = json_response(conn, 200)
    end
  end
end
