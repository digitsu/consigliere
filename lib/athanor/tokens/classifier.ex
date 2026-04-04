defmodule Athanor.Tokens.Classifier do
  @moduledoc """
  Classifies transaction outputs as P2PKH, STAS, STAS3, or unknown.
  Delegates to BSV.Tokens.Script.Reader for STAS script pattern matching.
  """

  alias BSV.Tokens.Script.Reader

  @doc """
  Classifies a locking script binary by type.

  ## Parameters
    - `script_binary` — raw locking script bytes

  ## Returns
    `:p2pkh` | `:stas` | `:stas_btg` | `:stas3` | `:op_return` | `:unknown`
  """
  @spec classify(binary()) :: atom()
  def classify(script_binary) when is_binary(script_binary) do
    parsed = Reader.read_locking_script(script_binary)
    parsed.script_type
  end

  @doc """
  Classifies a locking script from hex string.
  """
  @spec classify_hex(String.t()) :: atom()
  def classify_hex(script_hex) when is_binary(script_hex) do
    case Base.decode16(script_hex, case: :mixed) do
      {:ok, binary} -> classify(binary)
      :error -> :unknown
    end
  end

  @doc """
  Classifies all outputs of a parsed transaction.

  ## Returns
    List of `{vout, script_type, token_id | nil}` tuples.
  """
  @spec classify_outputs(BSV.Transaction.t()) :: [{non_neg_integer(), atom(), String.t() | nil}]
  def classify_outputs(%BSV.Transaction{outputs: outputs}) do
    outputs
    |> Enum.with_index()
    |> Enum.map(fn {output, vout} ->
      script_binary = BSV.Script.to_binary(output.locking_script)
      parsed = Reader.read_locking_script(script_binary)

      token_id =
        case parsed.script_type do
          type when type in [:stas, :stas_btg] ->
            BSV.Tokens.TokenId.to_string(parsed.stas.token_id)

          :stas3 ->
            Base.encode16(parsed.stas3.owner, case: :lower)

          _ ->
            nil
        end

      {vout, parsed.script_type, token_id}
    end)
  end
end
