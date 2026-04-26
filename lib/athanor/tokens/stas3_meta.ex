defmodule Athanor.Tokens.Stas3Meta do
  @moduledoc """
  Helpers for inspecting STAS 3.0 locking-script metadata used by the
  indexer when persisting / validating issuance state.

  Two responsibilities:

    * `post_op_return/1` — return the byte sequence that follows the
      `OP_RETURN` (0x6A) inside a STAS 3.0 locking script. Spec v0.1 §4
      requires this region to be byte-identical across every spend of a
      given protoID; the indexer uses this to detect tampered outputs.

    * `service_authorities/1` — walk the parsed `service_fields` list of
      a `BSV.Tokens.Script.Stas3Fields` struct and resolve the optional
      20-byte `freezeAuth` / `confiscateAuth` HASH160s based on the
      issuance flags byte (spec §5.2.3). Authorities appear in left-to-
      right order of increasing flag bit (FREEZABLE first, then
      CONFISCATABLE).
  """

  alias BSV.Tokens.Script.Stas3Fields
  alias BSV.Tokens.ScriptFlags

  @doc """
  Extract the bytes that follow `OP_RETURN` (0x6A) in a STAS 3.0 locking
  script. Returns `{:ok, bytes}` or `{:error, :no_op_return}` if no
  marker can be found.

  Spec v0.1 §4: the engine enforces that this region is byte-identical
  across every spend of an issuance. The indexer compares the stored
  canonical bytes against subsequent observations to detect a malformed
  transaction.

  The STAS 3.0 engine template ends in `OP_RETURN` and `0x6A` may appear
  earlier in the engine bytecode as a non-opcode literal. We anchor on
  the LAST `0x6A` and validate that the bytes after it parse as the
  expected sequence (`<redemption:20> <flags> <service_fields...>`).
  This matches the offset used by `BSV.Tokens.Script.Reader.parse_stas3/1`
  (`@stas3_base_template_len - 1`).
  """
  @spec post_op_return(binary()) :: {:ok, binary()} | {:error, :no_op_return}
  def post_op_return(script_binary) when is_binary(script_binary) do
    positions =
      :binary.matches(script_binary, <<0x6A>>)
      |> Enum.map(fn {pos, _} -> pos end)

    case last_valid_op_return(script_binary, Enum.reverse(positions)) do
      nil -> {:error, :no_op_return}
      pos -> {:ok, binary_part(script_binary, pos + 1, byte_size(script_binary) - pos - 1)}
    end
  end

  # Walk candidate OP_RETURN positions from last → first, returning the
  # first one whose tail decodes into a 20-byte redemption push followed
  # by at least one more push (the flags byte). Anything else is engine
  # bytecode that happens to contain a 0x6A literal.
  defp last_valid_op_return(_script, []), do: nil

  defp last_valid_op_return(script, [pos | rest]) do
    tail = binary_part(script, pos + 1, byte_size(script) - pos - 1)

    case BSV.Tokens.Script.Reader.parse_push_data_items(tail) do
      [<<_::binary-size(20)>>, _flags | _] -> pos
      _ -> last_valid_op_return(script, rest)
    end
  end

  @doc """
  Resolve the `freeze_auth` / `confiscate_auth` HASH160 service-field
  authorities for a parsed STAS 3.0 frame.

  Returns `{:ok, %{freeze_auth: bin_or_nil, confiscate_auth: bin_or_nil}}`
  on success; either field is `nil` when the corresponding flag bit is
  unset.

  Per spec v0.1 §5.2.3:
    * bit 0 (FREEZABLE) — when set, the next service field IS freezeAuth.
    * bit 1 (CONFISCATABLE) — when set, the following service field IS
      confiscateAuth.

  Service fields appear in left-to-right order of increasing flag bit
  (FREEZABLE first if present, then CONFISCATABLE). If only
  CONFISCATABLE is set, the FIRST service field IS confiscateAuth.
  """
  @spec service_authorities(Stas3Fields.t()) ::
          {:ok, %{freeze_auth: binary() | nil, confiscate_auth: binary() | nil}}
          | {:error, atom()}
  def service_authorities(%Stas3Fields{flags: flags, service_fields: service_fields}) do
    with {:ok, parsed_flags} <- ScriptFlags.decode(flags) do
      do_pick(parsed_flags, service_fields)
    end
  end

  defp do_pick(%ScriptFlags{freezable: false, confiscatable: false}, _fields) do
    {:ok, %{freeze_auth: nil, confiscate_auth: nil}}
  end

  defp do_pick(%ScriptFlags{freezable: true, confiscatable: false}, fields) do
    {:ok, %{freeze_auth: take_pkh(fields, 0), confiscate_auth: nil}}
  end

  defp do_pick(%ScriptFlags{freezable: false, confiscatable: true}, fields) do
    {:ok, %{freeze_auth: nil, confiscate_auth: take_pkh(fields, 0)}}
  end

  defp do_pick(%ScriptFlags{freezable: true, confiscatable: true}, fields) do
    {:ok, %{freeze_auth: take_pkh(fields, 0), confiscate_auth: take_pkh(fields, 1)}}
  end

  # Fetch the service field at `idx`, returning it only if it is exactly
  # a 20-byte HASH160. Anything else is treated as missing.
  defp take_pkh(fields, idx) do
    case Enum.at(fields, idx) do
      <<pkh::binary-size(20)>> -> pkh
      _ -> nil
    end
  end
end
