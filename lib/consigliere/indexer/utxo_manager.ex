defmodule Consigliere.Indexer.UtxoManager do
  @moduledoc """
  Manages the UTXO set in PostgreSQL. Provides functions to create UTXOs,
  mark them as spent, and query unspent outputs by address or token.

  This is a plain module (not a GenServer) — UTXO operations are stateless
  database queries that can be called from any process.

  TODO: Implement UTXO CRUD and balance queries in Phase 3.
  """

  alias Consigliere.Repo
  alias Consigliere.Schema.Utxo
  import Ecto.Query

  @doc """
  Returns all unspent UTXOs for a given address.

  ## Parameters
    - `address` — BSV address string

  ## Returns
    List of `Utxo` structs where `is_spent` is false.
  """
  def list_unspent(address) do
    # TODO: Implement in Phase 3
    Utxo
    |> where([u], u.address == ^address and u.is_spent == false)
    |> Repo.all()
  end

  @doc """
  Returns all unspent token UTXOs for a given token ID and optional address.

  ## Parameters
    - `token_id` — STAS token ID string
    - `address` — (optional) BSV address to filter by

  ## Returns
    List of `Utxo` structs matching the token and address filters.
  """
  def list_token_utxos(token_id, address \\ nil) do
    # TODO: Implement in Phase 3
    query = Utxo |> where([u], u.token_id == ^token_id and u.is_spent == false)

    query =
      if address do
        where(query, [u], u.address == ^address)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Creates a new UTXO record.

  ## Parameters
    - `attrs` — map with :txid, :vout, :address, :satoshis, :script_hex, etc.

  ## Returns
    `{:ok, utxo}` or `{:error, changeset}`
  """
  def create_utxo(attrs) do
    # TODO: Implement in Phase 3
    %Utxo{}
    |> Utxo.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Marks a UTXO as spent by the given transaction.

  ## Parameters
    - `txid` — the UTXO's transaction ID
    - `vout` — the UTXO's output index
    - `spent_txid` — the transaction ID that spends this UTXO

  ## Returns
    `{:ok, utxo}` or `{:error, reason}`
  """
  def spend_utxo(txid, vout, spent_txid) do
    # TODO: Implement in Phase 3
    case Repo.get_by(Utxo, txid: txid, vout: vout) do
      nil ->
        {:error, :not_found}

      utxo ->
        utxo
        |> Utxo.changeset(%{is_spent: true, spent_txid: spent_txid})
        |> Repo.update()
    end
  end
end
