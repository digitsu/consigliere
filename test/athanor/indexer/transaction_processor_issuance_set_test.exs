defmodule Athanor.Indexer.TransactionProcessorIssuanceSetTest do
  @moduledoc """
  Executable spec for STAS 3.0 issuance-set tagging at indexing time.

  Mirrors the production invariants enforced by dxs-consigliere's
  MetaTransaction patch (see
  `dxs-consigliere/src/Dxs.Consigliere/Services/Impl/TransactionStore.cs`
  lines 81-188):

    * **Valid issuance** — tx has STAS3 outputs, zero STAS inputs, a single
      protoID across outputs, and that protoID equals `HASH160(Vin[0])`
      (the pubkey hash of the spent P2PKH funding the issuance). The
      output is tagged into the issuance set; the tx is marked
      `is_valid_issue=true`.

    * **Forged issuance** — same shape but protoID does NOT match
      `HASH160(Vin[0])`. The output MUST NOT be tagged with the claimed
      protoID — otherwise an attacker can hijack any victim's issuance
      set by minting a P2STAS-templated output whose script self-asserts
      the victim's pubkey hash as protoID. The tx is marked
      `is_issue=true, is_valid_issue=false`.

    * **Transfer inheritance** — tx spends a previously-tagged STAS3 UTXO
      and produces STAS3 outputs with the same protoID. `Vin[0]` is now
      the owner's STAS3 input (its HASH160 is the owner PKH, not the
      protoID), so the issuance check is irrelevant. The output inherits
      the issuance-set tag from the spent parent UTXO; the tx is marked
      `is_issue=false`.

  ## Status

  These tests are expected to **fail** against the current
  `Athanor.Indexer.TransactionProcessor`:

    * Test 1 partially passes (output IS tagged today, but for the wrong
      reason — the indexer trusts the script's protoID unconditionally).
      The `is_valid_issue` / `is_issue` / `all_stas_inputs_known` /
      `illegal_roots` flag assertions all fail because `meta.metadata`
      is currently `%{}`.

    * Test 2 fails outright — the current indexer tags ANY STAS3 output
      with its script-embedded protoID, including forgeries.

    * Test 3 partially passes for the same reason as Test 1 (token_id is
      currently lifted from the script, which coincidentally matches the
      inherited value); flag assertions fail.

  Treat this file as a PRD-as-code for the eventual port of
  `UpdateStasAttributesQuery` to the Elixir indexer. The flag namespace
  used here (`meta.metadata["is_valid_issue"]` etc.) is a transitional
  shape — dedicated columns on `meta_transactions` would be cleaner and
  match the C# schema more directly. Either is fine; the test asserts
  the *contract*, not the storage layout.
  """

  use Athanor.DataCase, async: false

  alias Athanor.Indexer.TransactionProcessor
  alias Athanor.Repo
  alias Athanor.Schema.{MetaTransaction, Utxo}
  alias BSV.Tokens.Script.Stas3Builder

  setup do
    case Process.whereis(TransactionProcessor) do
      nil -> start_supervised!(TransactionProcessor)
      _ -> :ok
    end

    :ok
  end

  ## ── Fixture helpers ──

  # Mainnet P2PKH base58 address for a given 20-byte HASH160.
  defp p2pkh_address(<<hash160::binary-size(20)>>) do
    {:ok, addr} =
      hash160
      |> BSV.Script.p2pkh_lock()
      |> BSV.Script.Address.from_script()

    addr
  end

  # Insert a P2PKH UTXO row representing the funding input the issuance tx
  # will spend. Returns `{source_txid, source_vout}` for use in Vin[0]'s
  # `source_txid` / `source_tx_out_index` fields.
  defp insert_source_p2pkh_utxo(<<hash160::binary-size(20)>>, opts \\ []) do
    source_txid = Keyword.get(opts, :txid, :crypto.strong_rand_bytes(32))
    vout = Keyword.get(opts, :vout, 0)
    script_bin = hash160 |> BSV.Script.p2pkh_lock() |> BSV.Script.to_binary()

    {:ok, _utxo} =
      %Utxo{}
      |> Utxo.changeset(%{
        txid: source_txid,
        vout: vout,
        address: p2pkh_address(hash160),
        satoshis: 100_000,
        script_hex: Base.encode16(script_bin, case: :lower),
        is_spent: false
      })
      |> Repo.insert()

    {source_txid, vout}
  end

  defp build_stas3_script(proto, opts \\ []) do
    owner = Keyword.get(opts, :owner, :binary.copy(<<0xAA>>, 20))
    flags = Keyword.get(opts, :flags, %BSV.Tokens.ScriptFlags{})
    service_fields = Keyword.get(opts, :service_fields, [])

    {:ok, script} =
      Stas3Builder.build_stas3_locking_script(
        owner,
        proto,
        nil,
        false,
        flags,
        service_fields,
        []
      )

    script
  end

  defp build_tx(source_txid, source_vout, output_script, opts \\ []) do
    satoshis = Keyword.get(opts, :satoshis, 1_000)

    %BSV.Transaction{
      version: 1,
      lock_time: 0,
      inputs: [
        %BSV.Transaction.Input{
          source_txid: source_txid,
          source_tx_out_index: source_vout,
          sequence_number: 0xFFFFFFFF,
          unlocking_script: %BSV.Script{chunks: []}
        }
      ],
      outputs: [%BSV.Transaction.Output{satoshis: satoshis, locking_script: output_script}]
    }
  end

  ## ── Tests ──

  describe "STAS 3.0 issuance-set membership (spec v0.1 §5.2.1 / §14)" do
    test "valid issuance: protoID == HASH160(Vin[0]) tags the output into the issuance set" do
      # Issuer's P2PKH funding input. `issuer_pkh` is both the HASH160
      # of the spending pubkey AND the protoID embedded in the STAS3
      # output script — this match is what makes the tx a valid issuance.
      issuer_pkh = :binary.copy(<<0xAB>>, 20)
      proto_hex = Base.encode16(issuer_pkh, case: :lower)

      {source_txid, source_vout} = insert_source_p2pkh_utxo(issuer_pkh)

      stas3_script = build_stas3_script(issuer_pkh)
      tx = build_tx(source_txid, source_vout, stas3_script)

      {:ok, _txid_hex} = TransactionProcessor.process_tx(tx, [], [])

      txid_bin = BSV.Transaction.txid_binary(tx)
      utxo = Repo.get_by!(Utxo, txid: txid_bin, vout: 0)

      # Output IS tagged with the protoID — confirmed issuance-set member.
      assert utxo.token_id == proto_hex
      assert utxo.token_type == "stas3"

      # MetaTransaction carries the validation flag set
      # (dxs-consigliere `MetaTransaction.cs`). Stored under `metadata`
      # JSONB until/unless dedicated columns are added.
      meta = Repo.get_by!(MetaTransaction, txid: txid_bin)
      assert meta.metadata["is_stas"] == true
      assert meta.metadata["is_issue"] == true
      assert meta.metadata["is_valid_issue"] == true
      assert meta.metadata["all_stas_inputs_known"] == true
      assert meta.metadata["illegal_roots"] == []
    end

    test "forged issuance: protoID != HASH160(Vin[0]) — output is NOT tagged" do
      # Real issuer's pubkey hash (the one signing Vin[0]).
      issuer_pkh = :binary.copy(<<0x11>>, 20)
      # An UNRELATED protoID the attacker embeds in the STAS3 script,
      # attempting to mint into someone else's issuance set.
      forged_proto = :binary.copy(<<0x22>>, 20)
      forged_proto_hex = Base.encode16(forged_proto, case: :lower)

      {source_txid, source_vout} = insert_source_p2pkh_utxo(issuer_pkh)

      stas3_script = build_stas3_script(forged_proto)
      tx = build_tx(source_txid, source_vout, stas3_script)

      {:ok, _txid_hex} = TransactionProcessor.process_tx(tx, [], [])

      txid_bin = BSV.Transaction.txid_binary(tx)
      utxo = Repo.get_by(Utxo, txid: txid_bin, vout: 0)

      # The UTXO row may exist (the output is a real on-chain UTXO and
      # we still need to track its satoshis for balance purposes), but
      # it MUST NOT carry the claimed `forged_proto` tag.
      if utxo do
        refute utxo.token_id == forged_proto_hex,
               "forged issuance must not be tagged with the claimed protoID — " <>
                 "Vin[0]'s HASH160 (#{Base.encode16(issuer_pkh, case: :lower)}) " <>
                 "does not match the script's protoID (#{forged_proto_hex})"

        assert is_nil(utxo.token_id),
               "forged issuance output should have no issuance-set tag at all"
      end

      meta = Repo.get_by!(MetaTransaction, txid: txid_bin)
      assert meta.metadata["is_stas"] == true
      assert meta.metadata["is_issue"] == true
      assert meta.metadata["is_valid_issue"] == false
    end

    test "transfer: STAS3 output inherits issuance-set tag from a spent tagged UTXO" do
      issuer_pkh = :binary.copy(<<0x33>>, 20)
      proto = issuer_pkh
      proto_hex = Base.encode16(proto, case: :lower)

      # ─ 1. Issuance ─────────────────────────────────────────────
      # Stand up a valid issuance tx so its STAS3 output is correctly
      # tagged in the local UTXO set. This is the parent UTXO the
      # transfer will spend.
      {issuer_txid, issuer_vout} = insert_source_p2pkh_utxo(issuer_pkh)
      issuance_script = build_stas3_script(proto)
      issuance_tx = build_tx(issuer_txid, issuer_vout, issuance_script)

      {:ok, _} = TransactionProcessor.process_tx(issuance_tx, [], [])

      issuance_txid_bin = BSV.Transaction.txid_binary(issuance_tx)

      # Sanity: parent's STAS3 UTXO is in fact tagged.
      parent_utxo = Repo.get_by!(Utxo, txid: issuance_txid_bin, vout: 0)
      assert parent_utxo.token_id == proto_hex

      # ─ 2. Transfer ─────────────────────────────────────────────
      # Owner now spends the issuance UTXO and re-mints a STAS3 output
      # with the same protoID but a new owner PKH. Critically: Vin[0]'s
      # HASH160 here is the *owner* of the issuance UTXO, NOT `proto`,
      # so the issuance check (`HASH160(Vin[0]) == protoID`) MUST fail.
      # The child output inherits the tag because the parent UTXO is
      # already in the issuance set for `proto`.
      new_owner_pkh = :binary.copy(<<0xCC>>, 20)
      transfer_script = build_stas3_script(proto, owner: new_owner_pkh)
      transfer_tx = build_tx(issuance_txid_bin, 0, transfer_script)

      {:ok, _} = TransactionProcessor.process_tx(transfer_tx, [], [])

      transfer_txid_bin = BSV.Transaction.txid_binary(transfer_tx)
      child_utxo = Repo.get_by!(Utxo, txid: transfer_txid_bin, vout: 0)

      assert child_utxo.token_id == proto_hex,
             "transfer output should inherit token_id from the spent issuance UTXO"

      assert child_utxo.token_type == "stas3"

      meta = Repo.get_by!(MetaTransaction, txid: transfer_txid_bin)
      assert meta.metadata["is_stas"] == true

      assert meta.metadata["is_issue"] == false,
             "a tx with a STAS3 input is a transfer, not an issuance"

      assert meta.metadata["all_stas_inputs_known"] == true
      assert meta.metadata["illegal_roots"] == []
    end
  end
end
