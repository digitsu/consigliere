defmodule Athanor.Tokens.ClassifierTest do
  @moduledoc """
  Tests for output classification, in particular the M1 invariant that
  STAS 3.0 outputs are keyed by their `protoID` (HASH160 of the
  issuer/redemption address — spec v0.1 §5.2.1, §14) rather than the
  per-UTXO owner PKH.
  """

  use ExUnit.Case, async: true

  alias Athanor.Tokens.Classifier
  alias BSV.Tokens.Script.Stas3Builder

  defp build_stas3_output(owner, redemption) do
    {:ok, script} =
      Stas3Builder.build_stas3_locking_script(
        owner,
        redemption,
        nil,
        false,
        false,
        [],
        []
      )

    %BSV.Transaction.Output{satoshis: 1, locking_script: script}
  end

  describe "classify_outputs/1" do
    test "STAS 3.0 token-id is the redemption PKH (protoID), not the owner" do
      owner = :binary.copy(<<0xAA>>, 20)
      proto = :binary.copy(<<0xCD>>, 20)
      output = build_stas3_output(owner, proto)

      tx = %BSV.Transaction{inputs: [], outputs: [output]}
      [{0, :stas3, token_id}] = Classifier.classify_outputs(tx)

      assert token_id == Base.encode16(proto, case: :lower)
      refute token_id == Base.encode16(owner, case: :lower)
    end

    test "two outputs with the same protoID and DIFFERENT owners share token-id" do
      proto = :binary.copy(<<0xCD>>, 20)
      a = build_stas3_output(:binary.copy(<<0x01>>, 20), proto)
      b = build_stas3_output(:binary.copy(<<0x02>>, 20), proto)

      tx = %BSV.Transaction{inputs: [], outputs: [a, b]}
      results = Classifier.classify_outputs(tx)

      assert [{0, :stas3, id_a}, {1, :stas3, id_b}] = results
      assert id_a == id_b
      assert id_a == Base.encode16(proto, case: :lower)
    end
  end
end
