defmodule Athanor.Indexer.TransactionFilterP2mpkhTest do
  @moduledoc """
  TransactionFilter must match watched addresses that receive via the
  STAS 3.0 v0.1 §10.2 P2MPKH locking script — not only plain P2PKH.

  `matches?/1` reads the `:watched_addresses` ETS table directly (no
  GenServer round-trip), so the test populates that table itself rather
  than starting the real filter process.
  """

  use ExUnit.Case, async: false

  alias Athanor.Indexer.TransactionFilter
  alias BSV.Tokens.Script.Templates

  setup do
    # The filter reads two named, public ETS tables. The test-suite stub
    # does not create them, so we create (or clear) them here.
    for table <- [:watched_addresses, :watched_tokens] do
      case :ets.whereis(table) do
        :undefined -> :ets.new(table, [:set, :public, :named_table])
        _ -> :ets.delete_all_objects(table)
      end
    end

    :ok
  end

  defp p2mpkh_output(mpkh, satoshis) do
    {:ok, script} = BSV.Script.from_binary(Templates.p2mpkh_locking_script(mpkh))
    %BSV.Transaction.Output{satoshis: satoshis, locking_script: script}
  end

  defp tx_with_outputs(outputs) do
    %BSV.Transaction{
      version: 1,
      lock_time: 0,
      inputs: [
        %BSV.Transaction.Input{
          source_txid: :binary.copy(<<0x11>>, 32),
          source_tx_out_index: 0,
          sequence_number: 0xFFFFFFFF,
          unlocking_script: %BSV.Script{chunks: []}
        }
      ],
      outputs: outputs
    }
  end

  test "matches a watched address paid via a P2MPKH output" do
    mpkh = :binary.copy(<<0x7C>>, 20)
    address = BSV.Base58.check_encode(mpkh, 0x00)
    :ets.insert(:watched_addresses, {address, true})

    tx = tx_with_outputs([p2mpkh_output(mpkh, 4200)])

    {matched_addresses, _matched_tokens} = TransactionFilter.matches?(tx)
    assert address in matched_addresses
  end

  test "does not match an unwatched P2MPKH address" do
    watched_mpkh = :binary.copy(<<0x7C>>, 20)
    :ets.insert(:watched_addresses, {BSV.Base58.check_encode(watched_mpkh, 0x00), true})

    # A P2MPKH output to a DIFFERENT mpkh — must not match.
    other_mpkh = :binary.copy(<<0x3D>>, 20)
    tx = tx_with_outputs([p2mpkh_output(other_mpkh, 4200)])

    {matched_addresses, _} = TransactionFilter.matches?(tx)
    assert matched_addresses == []
  end
end
