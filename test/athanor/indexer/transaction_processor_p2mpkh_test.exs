defmodule Athanor.Indexer.TransactionProcessorP2mpkhTest do
  @moduledoc """
  P2MPKH support in the indexer (STAS 3.0 v0.1 §10.2).

  STAS 3.0 uses a fixed 70-byte P2MPKH locking script at issuance and
  redemption boundaries — `OP_DUP OP_HASH160 <MPKH:20> <47-byte suffix>`.
  The MPKH sits at offset 3, exactly like a P2PKH pubkey-hash, so it
  base58-encodes into an ordinary mainnet address.

  Covers:
    * a P2MPKH output is indexed with an MPKH-derived `address`
    * a STAS 3.0 redemption paying a P2MPKH output is flagged `is_redeem`
      (the redemption boundary is P2MPKH, not P2PKH)
  """

  use Athanor.DataCase, async: false

  alias Athanor.Indexer.TransactionProcessor
  alias Athanor.Repo
  alias Athanor.Schema.{MetaTransaction, Utxo}
  alias BSV.Tokens.Script.{Stas3Builder, Templates}

  setup do
    case Process.whereis(TransactionProcessor) do
      nil -> start_supervised!(TransactionProcessor)
      _ -> :ok
    end

    :ok
  end

  defp p2mpkh_script(mpkh) do
    {:ok, script} = BSV.Script.from_binary(Templates.p2mpkh_locking_script(mpkh))
    script
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
      %Utxo{}
      |> Utxo.changeset(%{
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

  test "a P2MPKH output is indexed with an MPKH-derived base58 address" do
    mpkh = :binary.copy(<<0x9A>>, 20)
    expected_address = BSV.Base58.check_encode(mpkh, 0x00)

    tx = %BSV.Transaction{
      version: 1,
      lock_time: 0,
      inputs: [single_input(:binary.copy(<<0x11>>, 32), 0)],
      outputs: [%BSV.Transaction.Output{satoshis: 5000, locking_script: p2mpkh_script(mpkh)}]
    }

    {:ok, _} = TransactionProcessor.process_tx(tx, [], [])

    utxo = Repo.get_by!(Utxo, txid: BSV.Transaction.txid_binary(tx), vout: 0)
    assert utxo.address == expected_address
    assert utxo.satoshis == 5000
  end

  test "a STAS 3.0 redemption to a P2MPKH output is flagged is_redeem" do
    # Valid issuance: protoID == HASH160(Vin[0]).
    issuer_pkh = :crypto.strong_rand_bytes(20)
    source_txid = insert_p2pkh_source_utxo(issuer_pkh)
    issuance_script = build_stas3_script(issuer_pkh, issuer_pkh)

    issuance_tx = %BSV.Transaction{
      version: 1,
      lock_time: 0,
      inputs: [single_input(source_txid, 0)],
      outputs: [%BSV.Transaction.Output{satoshis: 1000, locking_script: issuance_script}]
    }

    {:ok, _} = TransactionProcessor.process_tx(issuance_tx, [], [])
    issuance_txid_bin = BSV.Transaction.txid_binary(issuance_tx)

    # Redeem: spend the STAS3 UTXO, pay a P2MPKH output whose MPKH is the
    # protoID (the redemption boundary is P2MPKH per STAS 3.0 §10.2).
    redeem_tx = %BSV.Transaction{
      version: 1,
      lock_time: 0,
      inputs: [single_input(issuance_txid_bin, 0)],
      outputs: [
        %BSV.Transaction.Output{satoshis: 1000, locking_script: p2mpkh_script(issuer_pkh)}
      ]
    }

    {:ok, _} = TransactionProcessor.process_tx(redeem_tx, [], [])

    meta = Repo.get_by!(MetaTransaction, txid: BSV.Transaction.txid_binary(redeem_tx))
    assert meta.metadata["is_redeem"] == true
    assert meta.metadata["redeem_address"] == BSV.Base58.check_encode(issuer_pkh, 0x00)
  end
end
