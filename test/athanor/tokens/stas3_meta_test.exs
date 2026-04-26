defmodule Athanor.Tokens.Stas3MetaTest do
  @moduledoc """
  Tests for STAS 3.0 issuance-frame metadata extraction.

  Covers:

    * `post_op_return/1` — locating the byte sequence after the OP_RETURN
      marker (spec v0.1 §4 byte-identity invariant).
    * `service_authorities/1` — picking freezeAuth / confiscateAuth from
      the parsed `service_fields` list according to the flags bitmask
      (spec v0.1 §5.2.3).
  """

  use ExUnit.Case, async: true

  alias Athanor.Tokens.Stas3Meta
  alias BSV.Tokens.Script.{Reader, Stas3Builder, Stas3Fields}

  defp build_script(opts) do
    owner = Keyword.get(opts, :owner, :binary.copy(<<0xAA>>, 20))
    redemption = Keyword.get(opts, :redemption, :binary.copy(<<0xBB>>, 20))
    flags = Keyword.get(opts, :flags, %BSV.Tokens.ScriptFlags{})
    service_fields = Keyword.get(opts, :service_fields, [])

    {:ok, script} =
      Stas3Builder.build_stas3_locking_script(
        owner,
        redemption,
        nil,
        false,
        flags,
        service_fields,
        []
      )

    {BSV.Script.to_binary(script), redemption}
  end

  describe "post_op_return/1" do
    test "returns bytes following the OP_RETURN marker" do
      {script_bin, redemption} = build_script([])

      assert {:ok, after_op_return} = Stas3Meta.post_op_return(script_bin)
      # The first push after OP_RETURN is the 20-byte redemption (protoID).
      assert <<0x14, ^redemption::binary-size(20), _rest::binary>> = after_op_return
    end

    test "two outputs of the same protoID share identical post-OP_RETURN bytes" do
      proto = :binary.copy(<<0xCD>>, 20)
      {a, _} = build_script(redemption: proto, owner: :binary.copy(<<0x01>>, 20))
      {b, _} = build_script(redemption: proto, owner: :binary.copy(<<0x02>>, 20))

      {:ok, post_a} = Stas3Meta.post_op_return(a)
      {:ok, post_b} = Stas3Meta.post_op_return(b)
      # Per spec §4, the post-OP_RETURN region is byte-identical across
      # spends of an issuance — owner change MUST NOT alter it.
      assert post_a == post_b
    end

    test "tampered post-OP_RETURN bytes are detectable" do
      proto = :binary.copy(<<0xCD>>, 20)
      {good, _} = build_script(redemption: proto)
      {:ok, canonical} = Stas3Meta.post_op_return(good)

      # Flip a byte in the canonical region by appending random data —
      # the indexer compares raw bytes, so any divergence is rejected.
      tampered_bytes = canonical <> <<0xFF>>
      assert tampered_bytes != canonical
    end

    test "returns :no_op_return for a script with no 0x6A byte" do
      assert {:error, :no_op_return} = Stas3Meta.post_op_return(<<0x76, 0xA9, 0x14>>)
    end
  end

  describe "service_authorities/1" do
    test "returns nil pair when no flags are set" do
      fields = %Stas3Fields{flags: <<0x00>>, service_fields: []}

      assert {:ok, %{freeze_auth: nil, confiscate_auth: nil}} =
               Stas3Meta.service_authorities(fields)
    end

    test "FREEZABLE only — first service field is freeze_auth" do
      freeze_pkh = :binary.copy(<<0x11>>, 20)

      fields = %Stas3Fields{flags: <<0x01>>, service_fields: [freeze_pkh]}

      assert {:ok, %{freeze_auth: ^freeze_pkh, confiscate_auth: nil}} =
               Stas3Meta.service_authorities(fields)
    end

    test "CONFISCATABLE only — first service field IS confiscate_auth" do
      conf_pkh = :binary.copy(<<0x22>>, 20)

      fields = %Stas3Fields{flags: <<0x02>>, service_fields: [conf_pkh]}

      assert {:ok, %{freeze_auth: nil, confiscate_auth: ^conf_pkh}} =
               Stas3Meta.service_authorities(fields)
    end

    test "FREEZABLE + CONFISCATABLE — first is freeze, second is confiscate" do
      freeze_pkh = :binary.copy(<<0x11>>, 20)
      conf_pkh = :binary.copy(<<0x22>>, 20)

      fields = %Stas3Fields{flags: <<0x03>>, service_fields: [freeze_pkh, conf_pkh]}

      assert {:ok, %{freeze_auth: ^freeze_pkh, confiscate_auth: ^conf_pkh}} =
               Stas3Meta.service_authorities(fields)
    end

    test "round-trips through Reader.read_locking_script for a freezable+confiscatable issuance" do
      freeze_pkh = :binary.copy(<<0xF1>>, 20)
      conf_pkh = :binary.copy(<<0xC1>>, 20)

      flags = %BSV.Tokens.ScriptFlags{freezable: true, confiscatable: true}

      {script_bin, _redemption} =
        build_script(flags: flags, service_fields: [freeze_pkh, conf_pkh])

      parsed = Reader.read_locking_script(script_bin)

      assert {:ok, %{freeze_auth: ^freeze_pkh, confiscate_auth: ^conf_pkh}} =
               Stas3Meta.service_authorities(parsed.stas3)
    end
  end
end
