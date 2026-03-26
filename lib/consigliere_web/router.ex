defmodule ConsigliereWeb.Router do
  @moduledoc """
  Routes all REST API endpoints under /api.

  Admin routes provide CRUD for watched addresses/tokens and sync status.
  Address and Transaction routes serve indexed data (stubs until Phase 3).
  """

  use ConsigliereWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ConsigliereWeb do
    pipe_through :api

    # ── Admin endpoints ──
    post "/admin/manage/address", AdminController, :manage_address
    get "/admin/manage/addresses", AdminController, :list_addresses
    post "/admin/manage/stas-token", AdminController, :manage_stas_token
    get "/admin/manage/stas-tokens", AdminController, :list_stas_tokens
    get "/admin/blockchain/sync-status", AdminController, :sync_status

    # ── Address endpoints ──
    get "/address/:address/balance", AddressController, :balance
    get "/address/:address/history", AddressController, :history
    get "/address/:address/utxos", AddressController, :utxos

    # ── Transaction endpoints ──
    get "/transaction/:txid", TransactionController, :show
    post "/transaction/broadcast", TransactionController, :broadcast
  end
end
