defmodule Athanor.Indexer.TransactionProcessorStas3Test do
  @moduledoc """
  End-to-end indexer behaviour for STAS 3.0 (spec v0.1 §4 / §5.2.3 / §8.2):

    * M3 — first observation of a watched protoID seeds the canonical
      post-OP_RETURN bytes; a subsequent output with the same protoID but
      different post-OP_RETURN bytes is logged + skipped.
    * M4 — service-field authorities (freezeAuth / confiscateAuth) are
      lifted from the issuance frame onto the `WatchingToken` row when
      the corresponding flag bits are set.
  """

  use Athanor.DataCase, async: false

  import ExUnit.CaptureLog

  alias Athanor.Indexer.TransactionProcessor
  alias Athanor.Repo
  alias Athanor.Schema.{WatchingToken, Utxo}
  alias BSV.Tokens.Script.Stas3Builder

  setup do
    # The TransactionProcessor calls into UtxoManager + WatchingToken
    # against the SQL sandbox. Spawn the GenServer if it's not already up.
    case Process.whereis(TransactionProcessor) do
      nil -> start_supervised!(TransactionProcessor)
      _ -> :ok
    end

    :ok
  end

  defp build_stas3_script(opts) do
    owner = Keyword.get(opts, :owner, :binary.copy(<<0xAA>>, 20))
    proto = Keyword.fetch!(opts, :redemption)
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

  defp build_tx_with_output(script) do
    %BSV.Transaction{
      version: 1,
      lock_time: 0,
      inputs: [
        %BSV.Transaction.Input{
          # Non-coinbase: source_txid is non-zero so the processor takes
          # the spend-utxo branch even though we don't have a matching
          # UTXO row (UtxoManager.spend_utxo silently no-ops on misses).
          source_txid: :binary.copy(<<0x11>>, 32),
          source_tx_out_index: 0,
          sequence_number: 0xFFFFFFFF,
          unlocking_script: %BSV.Script{chunks: []}
        }
      ],
      outputs: [%BSV.Transaction.Output{satoshis: 1000, locking_script: script}]
    }
  end

  test "first STAS 3.0 output for a watched protoID seeds canonical bytes + service authorities" do
    proto = :binary.copy(<<0xCD>>, 20)
    proto_hex = Base.encode16(proto, case: :lower)

    freeze_pkh = :binary.copy(<<0xF1>>, 20)
    conf_pkh = :binary.copy(<<0xC1>>, 20)

    # Admin pre-registers the watched token by protoID.
    {:ok, _} =
      %WatchingToken{}
      |> WatchingToken.changeset(%{token_id: proto_hex})
      |> Repo.insert()

    flags = %BSV.Tokens.ScriptFlags{freezable: true, confiscatable: true}

    script =
      build_stas3_script(
        redemption: proto,
        flags: flags,
        service_fields: [freeze_pkh, conf_pkh]
      )

    tx = build_tx_with_output(script)

    {:ok, _txid} = TransactionProcessor.process_tx(tx, [], [proto_hex])

    refreshed = Repo.get_by!(WatchingToken, token_id: proto_hex)

    assert refreshed.canonical_post_op_return != nil
    assert byte_size(refreshed.canonical_post_op_return) > 0
    assert refreshed.freeze_auth == freeze_pkh
    assert refreshed.confiscate_auth == conf_pkh
  end

  test "tampered post-OP_RETURN payload is logged + skipped" do
    proto = :binary.copy(<<0xDE>>, 20)
    proto_hex = Base.encode16(proto, case: :lower)

    # Pre-seed the canonical bytes with a stub value that won't match
    # what the new output produces — emulating a previously-valid issuance
    # whose canonical region differs from the incoming malformed tx.
    canonical_stub = :crypto.strong_rand_bytes(64)

    {:ok, _} =
      %WatchingToken{}
      |> WatchingToken.changeset(%{
        token_id: proto_hex,
        canonical_post_op_return: canonical_stub
      })
      |> Repo.insert()

    script = build_stas3_script(redemption: proto)
    tx = build_tx_with_output(script)

    log =
      capture_log(fn ->
        {:ok, _txid} = TransactionProcessor.process_tx(tx, [], [proto_hex])
      end)

    assert log =~ "STAS3 post-OP_RETURN mismatch"

    # The output must NOT be indexed (canonical bytes diverge — spec §4
    # byte-identity invariant).
    txid_bin = BSV.Transaction.txid_binary(tx)
    assert nil == Repo.get_by(Utxo, txid: txid_bin, vout: 0)
  end
end
