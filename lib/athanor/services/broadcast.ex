defmodule Athanor.Services.Broadcast do
  @moduledoc """
  Handles transaction broadcasting via the BSV node RPC.
  Records each broadcast attempt in the broadcasts table for audit trail.
  """

  alias Athanor.Repo
  alias Athanor.Schema.Broadcast
  alias Athanor.Blockchain.RpcClient

  @doc """
  Broadcasts a raw transaction hex and records the attempt.

  ## Parameters
    - `raw_tx_hex` — raw transaction in hex encoding

  ## Returns
    `{:ok, broadcast}` with the created Broadcast record.
  """
  def broadcast_tx(raw_tx_hex) do
    # Compute txid from raw hex
    txid_hex =
      case BSV.Transaction.from_hex(raw_tx_hex) do
        {:ok, tx} -> BSV.Transaction.tx_id_hex(tx)
        {:error, _} -> "unknown"
      end

    # Create broadcast record
    {:ok, broadcast} =
      %Broadcast{}
      |> Broadcast.changeset(%{
        txid: txid_hex,
        hex: raw_tx_hex,
        status: "pending"
      })
      |> Repo.insert()

    # Actually broadcast via RPC
    case RpcClient.send_raw_transaction(raw_tx_hex) do
      {:ok, _returned_txid} ->
        broadcast
        |> Broadcast.changeset(%{status: "accepted"})
        |> Repo.update()

      {:error, reason} ->
        broadcast
        |> Broadcast.changeset(%{status: "rejected", error: inspect(reason)})
        |> Repo.update()
    end
  end

  @doc """
  Returns recent broadcast attempts.
  """
  def list_recent(limit \\ 20) do
    import Ecto.Query

    Broadcast
    |> order_by([b], desc: b.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end
end
