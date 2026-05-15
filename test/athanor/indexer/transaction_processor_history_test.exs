defmodule Athanor.Indexer.TransactionProcessorHistoryTest do
  @moduledoc """
  Address-history + balance behaviour for STAS 3.0 transactions.

  Covers four gaps found after the issuance-set indexing work:

    * Gap 1 — outbound STAS3 transfers produce a `direction="out"`
      address-history row for the watched sender, resolved from the
      spent UTXO (the filter only ever scanned outputs).
    * Gap 2 — `address_histories.token_id` is populated, so token-scoped
      history queries return rows.
    * Gap 3 — a STAS3 receive to a watched owner address is classified
      `direction="in"` (the owner address is now derived from the
      script, not the unextractable P2PKH template).
    * Gap 4 — forged-issuance STAS satoshis (token_type set, token_id
      nil) do NOT count toward the plain-BSV balance.
  """

  use Athanor.DataCase, async: false

  alias Athanor.Indexer.TransactionProcessor
  alias Athanor.Repo
  alias Athanor.Schema.{AddressHistory, Utxo, WatchingAddress}
  alias Athanor.Services.Balance
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

  defp watch_address(pkh) do
    address = BSV.Base58.check_encode(pkh, 0x00)

    {:ok, _} =
      %WatchingAddress{}
      |> WatchingAddress.changeset(%{address: address, name: "test"})
      |> Repo.insert()

    address
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

  defp build_tx(source_txid, source_vout, output_script, satoshis) do
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

  # Index a valid issuance so its STAS3 output is a real tagged UTXO that
  # a subsequent transfer can spend. Returns {issuance_txid_bin, proto_hex}.
  defp index_issuance(issuer_pkh) do
    proto = issuer_pkh
    source_txid = insert_p2pkh_source_utxo(issuer_pkh)
    script = build_stas3_script(proto, issuer_pkh)
    tx = build_tx(source_txid, 0, script, 1000)
    {:ok, _} = TransactionProcessor.process_tx(tx, [], [])
    {BSV.Transaction.txid_binary(tx), Base.encode16(proto, case: :lower)}
  end

  test "Gap 3 — STAS3 receive to a watched owner address logs a direction=in row" do
    issuer_pkh = :binary.copy(<<0xA1>>, 20)
    {issuance_txid_bin, proto_hex} = index_issuance(issuer_pkh)

    recipient_pkh = :binary.copy(<<0xA2>>, 20)
    recipient_addr = watch_address(recipient_pkh)

    transfer_script = build_stas3_script(issuer_pkh, recipient_pkh)
    transfer_tx = build_tx(issuance_txid_bin, 0, transfer_script, 1000)

    {:ok, _} = TransactionProcessor.process_tx(transfer_tx, [], [])

    hist = Repo.get_by!(AddressHistory, address: recipient_addr)
    assert hist.direction == "in"
    assert hist.satoshis == 1000
    assert hist.token_id == proto_hex
  end

  test "Gap 1 + 2 — outbound STAS3 transfer logs a direction=out row for the watched sender" do
    issuer_pkh = :binary.copy(<<0xB1>>, 20)
    {issuance_txid_bin, proto_hex} = index_issuance(issuer_pkh)

    # The issuance owner (issuer_pkh) is the sender of the transfer — its
    # STAS3 UTXO is what gets spent. Watch that owner address.
    sender_addr = watch_address(issuer_pkh)

    recipient_pkh = :binary.copy(<<0xB2>>, 20)
    transfer_script = build_stas3_script(issuer_pkh, recipient_pkh)
    transfer_tx = build_tx(issuance_txid_bin, 0, transfer_script, 1000)

    {:ok, _} = TransactionProcessor.process_tx(transfer_tx, [], [])

    transfer_txid_hex =
      transfer_tx |> BSV.Transaction.txid_binary() |> Base.encode16(case: :lower)

    # display order — the indexer stores txid in display order
    transfer_txid_display = BSV.Transaction.tx_id_hex(transfer_tx)

    hist =
      Repo.get_by(AddressHistory, address: sender_addr, direction: "out") ||
        Repo.get_by(AddressHistory, address: sender_addr)

    assert hist != nil, "watched sender must get an address-history row"
    assert hist.direction == "out"

    assert hist.satoshis == 1000,
           "out row amount should be the spent UTXO value, not 0"

    assert hist.token_id == proto_hex,
           "out row should carry the token_id of the spent STAS3 UTXO"

    assert hist.txid in [transfer_txid_display, transfer_txid_hex]
  end

  test "Gap 4 — forged-issuance STAS satoshis do not count as spendable BSV" do
    # Vin[0] is a P2PKH UTXO whose pubkey hash does NOT equal the protoID
    # the STAS3 script asserts — a forged issuance. The output is indexed
    # (token_type=stas3) but untagged (token_id=nil).
    issuer_pkh = :binary.copy(<<0xC1>>, 20)
    forged_proto = :binary.copy(<<0xC2>>, 20)

    source_txid = insert_p2pkh_source_utxo(issuer_pkh)
    owner_pkh = :binary.copy(<<0xC3>>, 20)
    owner_addr = BSV.Base58.check_encode(owner_pkh, 0x00)

    script = build_stas3_script(forged_proto, owner_pkh)
    tx = build_tx(source_txid, 0, script, 7777)

    {:ok, _} = TransactionProcessor.process_tx(tx, [], [])

    txid_bin = BSV.Transaction.txid_binary(tx)
    utxo = Repo.get_by!(Utxo, txid: txid_bin, vout: 0)

    # Sanity: the output is indexed, STAS-typed, but untagged (forged).
    assert utxo.token_type == "stas3"
    assert is_nil(utxo.token_id)

    # The forged STAS satoshis must NOT show up as plain BSV balance —
    # they are locked behind the STAS3 script.
    assert Balance.get_balance(owner_addr) == 0
  end
end
