defmodule Athanor.Indexer.TransactionProcessorTaintTest do
  @moduledoc """
  Illegal-root taint propagation — port of dxs-consigliere's
  `illegalRoots` logic in `TransactionStore.cs:153-162`.

  A forged issuance (protoID != HASH160(Vin[0])) poisons its entire
  descendant lineage. Every transfer downstream of a forged root must:

    * carry the forged root's txid in `metadata["illegal_roots"]`
    * leave its outputs untagged (`utxos.token_id = nil`) — a tainted
      UTXO is not a valid member of any issuance set
    * NOT be stuck in deferred limbo: the forged parent IS indexed and
      settled, so `all_stas_inputs_known` must be true

  Because tainted outputs get `token_id = nil`, they are automatically
  excluded from `list_token_utxos`, `Balance` token totals, and every
  other consumer that filters on a non-nil `token_id` — that nulling IS
  Athanor's spendable-UTXO filter.
  """

  use Athanor.DataCase, async: false

  alias Athanor.Indexer.{TransactionProcessor, UtxoManager}
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

  defp build_tx(source_txid, source_vout, output_script) do
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
      outputs: [%BSV.Transaction.Output{satoshis: 1000, locking_script: output_script}]
    }
  end

  defp display_hex(<<_::binary-size(32)>> = txid_binary) do
    txid_binary
    |> :binary.bin_to_list()
    |> Enum.reverse()
    |> :binary.list_to_bin()
    |> Base.encode16(case: :lower)
  end

  # Build + index a FORGED issuance: Vin[0]'s pubkey hash deliberately
  # does NOT equal the protoID the STAS3 script asserts. Returns
  # {forged_txid_bin, claimed_proto}.
  defp index_forged_issuance(claimed_proto) do
    real_issuer_pkh = :crypto.strong_rand_bytes(20)
    source_txid = insert_p2pkh_source_utxo(real_issuer_pkh)
    owner = :crypto.strong_rand_bytes(20)
    script = build_stas3_script(claimed_proto, owner)
    tx = build_tx(source_txid, 0, script)
    {:ok, _} = TransactionProcessor.process_tx(tx, [], [])
    {BSV.Transaction.txid_binary(tx), claimed_proto}
  end

  test "transfer spending a forged issuance is tainted, not deferred" do
    claimed_proto = :binary.copy(<<0x5A>>, 20)
    {forged_txid_bin, _proto} = index_forged_issuance(claimed_proto)
    forged_hex = display_hex(forged_txid_bin)

    # Sanity: the forged issuance itself is untagged + flagged.
    forged_meta = Repo.get_by!(MetaTransaction, txid: forged_txid_bin)
    assert forged_meta.metadata["is_issue"] == true
    assert forged_meta.metadata["is_valid_issue"] == false
    assert forged_hex in forged_meta.metadata["illegal_roots"]

    # A transfer spends the forged issuance output.
    new_owner = :binary.copy(<<0x5B>>, 20)
    transfer_script = build_stas3_script(claimed_proto, new_owner)
    transfer_tx = build_tx(forged_txid_bin, 0, transfer_script)

    {:ok, _} = TransactionProcessor.process_tx(transfer_tx, [], [])

    transfer_txid_bin = BSV.Transaction.txid_binary(transfer_tx)
    meta = Repo.get_by!(MetaTransaction, txid: transfer_txid_bin)

    # The transfer must be RESOLVED (the forged parent is indexed and
    # settled) — not stuck waiting for a parent that will never "arrive".
    assert meta.metadata["all_stas_inputs_known"] == true
    assert meta.metadata["missing_transactions"] in [nil, []]

    # ...and TAINTED — the forged root poisons it.
    assert forged_hex in meta.metadata["illegal_roots"]

    utxo = Repo.get_by!(Utxo, txid: transfer_txid_bin, vout: 0)

    assert is_nil(utxo.token_id),
           "a transfer descended from a forged issuance must not be tagged"
  end

  test "taint propagates through a multi-hop transfer chain" do
    claimed_proto = :binary.copy(<<0x6A>>, 20)
    {forged_txid_bin, _} = index_forged_issuance(claimed_proto)
    forged_hex = display_hex(forged_txid_bin)

    # forged → T1 → T2
    t1_script = build_stas3_script(claimed_proto, :binary.copy(<<0x6B>>, 20))
    t1_tx = build_tx(forged_txid_bin, 0, t1_script)
    {:ok, _} = TransactionProcessor.process_tx(t1_tx, [], [])
    t1_txid_bin = BSV.Transaction.txid_binary(t1_tx)

    t2_script = build_stas3_script(claimed_proto, :binary.copy(<<0x6C>>, 20))
    t2_tx = build_tx(t1_txid_bin, 0, t2_script)
    {:ok, _} = TransactionProcessor.process_tx(t2_tx, [], [])
    t2_txid_bin = BSV.Transaction.txid_binary(t2_tx)

    for txid_bin <- [t1_txid_bin, t2_txid_bin] do
      meta = Repo.get_by!(MetaTransaction, txid: txid_bin)

      assert forged_hex in meta.metadata["illegal_roots"],
             "every descendant must carry the forged root in illegal_roots"

      assert meta.metadata["all_stas_inputs_known"] == true

      utxo = Repo.get_by!(Utxo, txid: txid_bin, vout: 0)
      assert is_nil(utxo.token_id)
    end
  end

  test "tainted UTXOs are excluded from token-set queries" do
    claimed_proto = :binary.copy(<<0x7A>>, 20)
    proto_hex = Base.encode16(claimed_proto, case: :lower)
    {forged_txid_bin, _} = index_forged_issuance(claimed_proto)

    transfer_script = build_stas3_script(claimed_proto, :binary.copy(<<0x7B>>, 20))
    transfer_tx = build_tx(forged_txid_bin, 0, transfer_script)
    {:ok, _} = TransactionProcessor.process_tx(transfer_tx, [], [])

    # Neither the forged issuance output nor the tainted transfer output
    # should surface as a spendable member of the (claimed) issuance set.
    assert UtxoManager.list_token_utxos(proto_hex) == []
  end

  test "out-of-order: transfer indexed before its forged parent ends tainted, not deferred" do
    claimed_proto = :binary.copy(<<0x8A>>, 20)

    # Build the forged issuance but DON'T index it yet.
    real_issuer_pkh = :crypto.strong_rand_bytes(20)
    source_txid = insert_p2pkh_source_utxo(real_issuer_pkh)
    forged_script = build_stas3_script(claimed_proto, :crypto.strong_rand_bytes(20))
    forged_tx = build_tx(source_txid, 0, forged_script)
    forged_txid_bin = BSV.Transaction.txid_binary(forged_tx)
    forged_hex = display_hex(forged_txid_bin)

    # Index the transfer FIRST — its parent is unknown, so it defers.
    transfer_script = build_stas3_script(claimed_proto, :binary.copy(<<0x8B>>, 20))
    transfer_tx = build_tx(forged_txid_bin, 0, transfer_script)
    {:ok, _} = TransactionProcessor.process_tx(transfer_tx, [], [])
    transfer_txid_bin = BSV.Transaction.txid_binary(transfer_tx)

    meta_before = Repo.get_by!(MetaTransaction, txid: transfer_txid_bin)
    assert meta_before.metadata["all_stas_inputs_known"] == false

    # Now the forged parent arrives. The transfer must be reprocessed
    # into a TAINTED (not deferred, not valid) state.
    {:ok, _} = TransactionProcessor.process_tx(forged_tx, [], [])

    meta_after = Repo.get_by!(MetaTransaction, txid: transfer_txid_bin)
    assert meta_after.metadata["all_stas_inputs_known"] == true
    assert meta_after.metadata["missing_transactions"] in [nil, []]
    assert forged_hex in meta_after.metadata["illegal_roots"]

    utxo = Repo.get_by!(Utxo, txid: transfer_txid_bin, vout: 0)
    assert is_nil(utxo.token_id)
  end
end
