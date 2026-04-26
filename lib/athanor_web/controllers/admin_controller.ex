defmodule AthanorWeb.AdminController do
  @moduledoc """
  Admin endpoints for managing watched addresses, STAS tokens, and sync status.

  These endpoints actually perform CRUD against the database (Phase 1).
  """

  use AthanorWeb, :controller

  alias Athanor.Repo
  alias Athanor.Schema.{WatchingAddress, WatchingToken}
  alias Athanor.Indexer.TransactionFilter
  alias Athanor.Services.SyncStatus

  @doc """
  POST /api/admin/manage/address — Adds an address to the watch list.

  ## Request body
    - `address` (required) — BSV address string
    - `name` (optional) — human-readable label

  ## Responses
    - 201: Address added successfully
    - 422: Validation error (missing address or duplicate)
  """
  def manage_address(conn, params) do
    %WatchingAddress{}
    |> WatchingAddress.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, address} ->
        # Register in ETS for fast tx matching on the hot path
        TransactionFilter.add_address(address.address)

        conn
        |> put_status(:created)
        |> json(%{
          id: address.id,
          address: address.address,
          name: address.name,
          inserted_at: address.inserted_at
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc """
  GET /api/admin/manage/addresses — Lists all watched addresses.

  ## Responses
    - 200: Array of watched address records.
  """
  def list_addresses(conn, _params) do
    addresses = Repo.all(WatchingAddress)

    json(conn, %{
      addresses:
        Enum.map(addresses, fn a ->
          %{id: a.id, address: a.address, name: a.name, inserted_at: a.inserted_at}
        end)
    })
  end

  @doc """
  POST /api/admin/manage/stas-token — Adds a STAS token to the watch list.

  ## Request body
    - `token_id` (required) — STAS token ID string
    - `symbol` (optional) — token symbol

  ## Responses
    - 201: Token added successfully
    - 422: Validation error (missing token_id or duplicate)
  """
  def manage_stas_token(conn, params) do
    %WatchingToken{}
    |> WatchingToken.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, token} ->
        # Register in ETS for fast tx matching on the hot path
        TransactionFilter.add_token(token.token_id)

        conn
        |> put_status(:created)
        |> json(token_view(token))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc """
  GET /api/admin/manage/stas-tokens — Lists all watched STAS tokens.

  ## Responses
    - 200: Array of watched token records.
  """
  def list_stas_tokens(conn, _params) do
    tokens = Repo.all(WatchingToken)
    json(conn, %{tokens: Enum.map(tokens, &token_view/1)})
  end

  # Render a `WatchingToken` for the admin API. STAS 3.0 service-field
  # authorities (spec v0.1 §5.2.3) are exposed as lowercase hex strings so
  # callers can compare against canonical addresses without dealing with
  # raw 20-byte binaries over JSON.
  defp token_view(%WatchingToken{} = t) do
    %{
      id: t.id,
      token_id: t.token_id,
      symbol: t.symbol,
      freeze_auth: hex_or_nil(t.freeze_auth),
      confiscate_auth: hex_or_nil(t.confiscate_auth),
      inserted_at: t.inserted_at
    }
  end

  defp hex_or_nil(nil), do: nil
  defp hex_or_nil(bin) when is_binary(bin), do: Base.encode16(bin, case: :lower)

  @doc """
  GET /api/admin/blockchain/sync-status — Returns chain sync status.

  ## Responses
    - 200: Sync status object with last_block_height, last_block_hash, is_synced.
  """
  def sync_status(conn, _params) do
    status = SyncStatus.get_status()
    json(conn, status)
  end

  # Formats changeset errors into a simple map for JSON responses.
  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
