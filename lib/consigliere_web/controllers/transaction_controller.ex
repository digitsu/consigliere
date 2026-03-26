defmodule ConsigliereWeb.TransactionController do
  @moduledoc """
  Transaction endpoints for fetching indexed transaction data and broadcasting.

  `show/2` looks up a MetaTransaction by txid from the database.
  `broadcast/2` delegates to the Broadcast service which records the attempt
  and (in Phase 2) relays to the BSV node via RPC.
  """

  use ConsigliereWeb, :controller

  alias Consigliere.Repo
  alias Consigliere.Schema.MetaTransaction
  alias Consigliere.Services.Broadcast
  import Ecto.Query

  @doc """
  GET /api/transaction/:txid — Fetches a transaction by its hex txid.

  ## Parameters
    - `txid` — transaction ID hex string (path param)

  ## Responses
    - 200: Transaction object
    - 404: Transaction not found
  """
  def show(conn, %{"txid" => txid_hex}) do
    # Decode hex txid to binary for DB lookup
    case Base.decode16(txid_hex, case: :mixed) do
      {:ok, txid_bin} ->
        case Repo.one(from m in MetaTransaction, where: m.txid == ^txid_bin) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "transaction not found"})

          meta_tx ->
            json(conn, %{
              txid: txid_hex,
              block_height: meta_tx.block_height,
              block_hash: encode_binary(meta_tx.block_hash),
              timestamp: meta_tx.timestamp,
              is_confirmed: meta_tx.is_confirmed,
              addresses: meta_tx.addresses,
              token_ids: meta_tx.token_ids,
              metadata: meta_tx.metadata
            })
        end

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid txid hex"})
    end
  end

  @doc """
  POST /api/transaction/broadcast — Broadcasts a raw transaction.

  ## Request body
    - `hex` (required) — raw transaction hex

  ## Responses
    - 201: Broadcast record with status
    - 422: Validation error (missing hex or broadcast failure)
  """
  def broadcast(conn, %{"hex" => hex}) do
    case Broadcast.broadcast_tx(hex) do
      {:ok, record} ->
        conn
        |> put_status(:created)
        |> json(%{
          txid: record.txid,
          status: record.status
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  def broadcast(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "missing required field: hex"})
  end

  # Encodes a binary field to lowercase hex, returning nil for nil input.
  defp encode_binary(nil), do: nil
  defp encode_binary(bin), do: Base.encode16(bin, case: :lower)

  # Formats changeset errors into a simple map for JSON responses.
  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
