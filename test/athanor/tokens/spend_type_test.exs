defmodule Athanor.Tokens.SpendTypeTest do
  @moduledoc """
  Tests for STAS 3.0 unlocking-script `spendType` extraction (spec v0.1
  §7 / §8.2 / §9.6). Builds synthetic unlocking scripts that match the
  spec's parameter sequence (20 push slots before spendType) and asserts
  the parser maps the byte to the correct operation atom.
  """

  use ExUnit.Case, async: true

  alias Athanor.Tokens.SpendType

  # Build a minimal STAS 3.0 unlocking script with `spend_type_byte` placed
  # at the spec-mandated push slot 20 (0-indexed 19). Slots 1–18 are
  # `OP_FALSE` empty pushes (= byte 0x00). Slot 19 is the BIP-143 sighash
  # preimage — represented here as a 100-byte filler push for realism.
  # Slot 20 is the spendType. Slot 21+ is the auth (single OP_FALSE push).
  defp synth_unlock(spend_type_byte) do
    op_false = <<0x00>>

    # 18 leading OP_FALSE pushes (slots 1..17 + txType placeholder slot 18).
    leading = :binary.copy(op_false, 18)

    # Slot 19 — sighash preimage, 100-byte filler. Use OP_PUSHDATA1 (0x4c)
    # so the parser sees a single push of exactly 100 bytes.
    preimage = :binary.copy(<<0xAB>>, 100)
    preimage_push = <<0x4C, byte_size(preimage)::8>> <> preimage

    # Slot 20 — spendType (1B). Use a direct push of length 1.
    spend_push = <<0x01, spend_type_byte>>

    # Slot 21 — auth (OP_FALSE empty push for arbitrator-free / no-sig case).
    auth_push = op_false

    leading <> preimage_push <> spend_push <> auth_push
  end

  describe "parse/1" do
    test "spendType=1 classifies as :transfer" do
      assert {:ok, :transfer} = SpendType.parse(synth_unlock(1))
    end

    test "spendType=2 classifies as :freeze_unfreeze" do
      assert {:ok, :freeze_unfreeze} = SpendType.parse(synth_unlock(2))
    end

    test "spendType=3 classifies as :confiscation" do
      assert {:ok, :confiscation} = SpendType.parse(synth_unlock(3))
    end

    test "spendType=4 classifies as :swap_cancel" do
      assert {:ok, :swap_cancel} = SpendType.parse(synth_unlock(4))
    end

    test "unknown byte returns :unknown_spend_type" do
      assert {:error, :unknown_spend_type} = SpendType.parse(synth_unlock(0))
      assert {:error, :unknown_spend_type} = SpendType.parse(synth_unlock(5))
    end

    test "empty / too-short script returns :not_enough_pushes" do
      assert {:error, :not_enough_pushes} = SpendType.parse(<<>>)
      assert {:error, :not_enough_pushes} = SpendType.parse(<<0x00, 0x00>>)
    end

    test "accepts a %BSV.Script{} struct" do
      bin = synth_unlock(3)
      {:ok, script} = BSV.Script.from_binary(bin)
      assert {:ok, :confiscation} = SpendType.parse(script)
    end
  end

  describe "from_byte/1" do
    test "maps spec bytes to atoms with :swap_cancellation collapsed" do
      assert {:ok, :transfer} = SpendType.from_byte(1)
      assert {:ok, :freeze_unfreeze} = SpendType.from_byte(2)
      assert {:ok, :confiscation} = SpendType.from_byte(3)
      assert {:ok, :swap_cancel} = SpendType.from_byte(4)
      assert {:error, :unknown_spend_type} = SpendType.from_byte(99)
    end
  end

  describe "to_string/1" do
    test "renders DB-friendly strings" do
      assert SpendType.to_string(:transfer) == "transfer"
      assert SpendType.to_string(:freeze_unfreeze) == "freeze_unfreeze"
      assert SpendType.to_string(:confiscation) == "confiscation"
      assert SpendType.to_string(:swap_cancel) == "swap_cancel"
    end
  end
end
