defmodule Athanor.Indexer.TransactionProcessorRedemptionTest do
  @moduledoc """
  STAS 3.0 redemption detection — port of dxs-consigliere's
  `IsRedeem` / `RedeemAddress` computation.

  A token is *redeemed* (burned back to plain BSV) when a transaction
  spends a STAS UTXO and pays a P2PKH output to the issuance's
  redemption address — the address whose HASH160 equals the protoID.
  The indexer flags such a transaction with:

    * `metadata["is_redeem"]` — true
    * `metadata["redeem_address"]` — the base58 redemption address

  A normal transfer (re-minting a STAS 3.0 output) is NOT a redemption.
  """

  use Athanor.DataCase, async: false

  alias Athanor.Indexer.TransactionProcessor
  alias Athanor.Repo
  alias Athanor.Schema.MetaTransaction
  alias BSV.Tokens.Script.Stas3Builder

  setup do
    case Process.whereis(TransactionProcessor) do
      nil -> start_supervised!(TransactionProcessor)
      _ -> :ok
    end

    :ok
  end

  defp build_stas3_script(proto, owner) do
    {:ok, script} =
      Stas3Builder.build_stas3_locking_script(
        owner,
        proto,
        nil,
        false,
        %BSV.Tokens.ScriptFlags{},
        [],
        []
      )

    script
  end

  defp insert_p2pkh_source_utxo(pkh) do
    source_txid = :crypto.strong_rand_bytes(32)
    script_bin = pkh |> BSV.Script.p2pkh_lock() |> BSV.Script.to_binary()

    {:ok, _} =
      %Athanor.Schema.Utxo{}
      |> Athanor.Schema.Utxo.changeset(%{
        txid: source_txid,
        vout: 0,
        address: BSV.Base58.check_encode(pkh, 0x00),
        satoshis: 100_000,
        script_hex: Base.encode16(script_bin, case: :lower),
        is_spent: false
      })
      |> Repo.insert()

    source_txid
  end

  defp single_input(source_txid, source_vout) do
    %BSV.Transaction.Input{
      source_txid: source_txid,
      source_tx_out_index: source_vout,
      sequence_number: 0xFFFFFFFF,
      unlocking_script: %BSV.Script{chunks: []}
    }
  end

  # Index a valid issuance; return {issuance_txid_bin, issuer_pkh}.
  defp index_issuance do
    issuer_pkh = :crypto.strong_rand_bytes(20)
    source_txid = insert_p2pkh_source_utxo(issuer_pkh)
    script = build_stas3_script(issuer_pkh, issuer_pkh)

    tx = %BSV.Transaction{
      version: 1,
      lock_time: 0,
      inputs: [single_input(source_txid, 0)],
      outputs: [%BSV.Transaction.Output{satoshis: 1000, locking_script: script}]
    }

    {:ok, _} = TransactionProcessor.process_tx(tx, [], [])
    {BSV.Transaction.txid_binary(tx), issuer_pkh}
  end

  test "redemption: spending a STAS3 UTXO to the redemption address is flagged is_redeem" do
    {issuance_txid_bin, issuer_pkh} = index_issuance()

    # The redemption address is the P2PKH address whose HASH160 is the
    # protoID — here, the issuer's own pubkey hash.
    redeem_addr = BSV.Base58.check_encode(issuer_pkh, 0x00)
    p2pkh_lock = BSV.Script.p2pkh_lock(issuer_pkh)

    redeem_tx = %BSV.Transaction{
      version: 1,
      lock_time: 0,
      inputs: [single_input(issuance_txid_bin, 0)],
      outputs: [%BSV.Transaction.Output{satoshis: 1000, locking_script: p2pkh_lock}]
    }

    {:ok, _} = TransactionProcessor.process_tx(redeem_tx, [], [])

    meta = Repo.get_by!(MetaTransaction, txid: BSV.Transaction.txid_binary(redeem_tx))
    assert meta.metadata["is_redeem"] == true
    assert meta.metadata["redeem_address"] == redeem_addr
    # A redemption still spends a STAS input — it's STAS, not an issuance.
    assert meta.metadata["is_stas"] == true
    assert meta.metadata["is_issue"] == false
  end

  test "normal transfer re-minting a STAS3 output is not a redemption" do
    {issuance_txid_bin, issuer_pkh} = index_issuance()

    # Re-mint a STAS3 output: same protoID (issuer_pkh), new owner.
    new_owner = :binary.copy(<<0x2C>>, 20)

    transfer_tx = %BSV.Transaction{
      version: 1,
      lock_time: 0,
      inputs: [single_input(issuance_txid_bin, 0)],
      outputs: [
        %BSV.Transaction.Output{
          satoshis: 1000,
          locking_script: build_stas3_script(issuer_pkh, new_owner)
        }
      ]
    }

    {:ok, _} = TransactionProcessor.process_tx(transfer_tx, [], [])

    meta = Repo.get_by!(MetaTransaction, txid: BSV.Transaction.txid_binary(transfer_tx))
    assert meta.metadata["is_redeem"] == false
    assert is_nil(meta.metadata["redeem_address"])
  end

  test "issuance transactions are never flagged as redemptions" do
    {issuance_txid_bin, _} = index_issuance()
    meta = Repo.get_by!(MetaTransaction, txid: issuance_txid_bin)
    assert meta.metadata["is_redeem"] == false
    assert is_nil(meta.metadata["redeem_address"])
  end
end
