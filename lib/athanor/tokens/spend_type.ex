defmodule Athanor.Tokens.SpendType do
  @moduledoc """
  STAS 3.0 unlocking-script `spendType` extraction.

  Per STAS 3.0 spec v0.1 §7 / §8.2, every STAS 3.0 unlocking script pushes a
  fixed sequence of parameters onto the stack. The 20th parameter
  (1-indexed in the spec, 0-indexed position 19 here) is the 1-byte
  `spendType`, which classifies the operation:

    | byte | label             | meaning                                        |
    |------|-------------------|------------------------------------------------|
    | 1    | `:transfer`       | Regular spend / split / merge / swap          |
    | 2    | `:freeze_unfreeze`| Freeze or unfreeze (FREEZABLE flag required)  |
    | 3    | `:confiscation`   | Forcible reassignment (CONFISCATABLE required)|
    | 4    | `:swap_cancel`    | Cancel a standing swap offer                  |

  The corresponding precedence order (spec §9.6) is:

      confiscation > freeze_unfreeze > swap_cancel > transfer

  This module surfaces the spendType class as a simple atom so the indexer
  can record the operation class on STAS 3.0 outputs (see
  `Athanor.Indexer.TransactionProcessor`).

  ## Pushdata layout

  The unlocking script is a sequence of Bitcoin pushdata items. Items 1–17
  are the optional output / change / note / funding-tx fields (each may be
  `OP_0`/`OP_FALSE` empty pushes). Item 18 is `txType` (1B), item 19 is
  the BIP-143 sighash preimage, item 20 is `spendType` (1B), item 21+ is
  the auth (sig + pubkey, or multisig stack, or `OP_0` for arbitrator-free).

  We rely on `BSV.Tokens.Script.Reader.parse_push_data_items/1`, which
  already handles every push opcode (OP_0, OP_1NEGATE, OP_1..OP_16,
  direct push, OP_PUSHDATA1/2/4) and is shared with the locking-script
  reader.
  """

  alias BSV.Tokens.Script.Reader
  alias BSV.Tokens.SpendType, as: BsvSpendType

  # 0-indexed position of the spendType push in a STAS 3.0 unlocking script.
  # Spec §7 lists it as parameter 20 (1-indexed).
  @spend_type_index 19

  @typedoc "High-level operation class derived from the STAS 3.0 spendType byte."
  @type op :: :transfer | :freeze_unfreeze | :confiscation | :swap_cancel | :unknown

  @doc """
  Parse the `spendType` byte from a STAS 3.0 unlocking script.

  Accepts a binary unlocking script (raw bytes) or a `%BSV.Script{}` struct.

  Returns `{:ok, op_atom}` for a recognised spendType, `{:error, reason}`
  otherwise. Reasons:
    * `:not_enough_pushes` — fewer than 20 pushdata items in the script.
    * `:not_a_byte` — push at the spendType slot is not exactly 1 byte.
    * `:unknown_spend_type` — byte value is not in [1, 4].

  ## Examples

      iex> {:ok, :confiscation} = Athanor.Tokens.SpendType.parse(<<...>>)

  """
  @spec parse(binary() | BSV.Script.t()) :: {:ok, op()} | {:error, atom()}
  def parse(%BSV.Script{} = script), do: parse(BSV.Script.to_binary(script))

  def parse(script_binary) when is_binary(script_binary) do
    items = Reader.parse_push_data_items(script_binary)

    cond do
      length(items) <= @spend_type_index ->
        {:error, :not_enough_pushes}

      true ->
        case Enum.at(items, @spend_type_index) do
          <<byte::8>> -> from_byte(byte)
          _ -> {:error, :not_a_byte}
        end
    end
  end

  @doc """
  Convert a STAS 3.0 spendType byte (per spec v0.1 §8.2) to the
  athanor-side operation atom.

  Delegates the byte→symbol mapping to `BSV.Tokens.SpendType.from_byte/1`
  (transfer / freeze_unfreeze / confiscation / swap_cancellation) and
  collapses `:swap_cancellation` to `:swap_cancel` for the database
  enum used on `utxos.stas3_op` and equivalent surfaces.
  """
  @spec from_byte(byte()) :: {:ok, op()} | {:error, :unknown_spend_type}
  def from_byte(byte) do
    case BsvSpendType.from_byte(byte) do
      {:ok, :swap_cancellation} -> {:ok, :swap_cancel}
      {:ok, op} -> {:ok, op}
      err -> err
    end
  end

  @doc """
  Convenience: stringify the spendType atom into the form persisted on
  the `utxos.stas3_op` column.
  """
  @spec to_string(op()) :: String.t()
  def to_string(:transfer), do: "transfer"
  def to_string(:freeze_unfreeze), do: "freeze_unfreeze"
  def to_string(:confiscation), do: "confiscation"
  def to_string(:swap_cancel), do: "swap_cancel"
  def to_string(:unknown), do: "unknown"
end
