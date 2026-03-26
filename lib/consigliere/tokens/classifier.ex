defmodule Consigliere.Tokens.Classifier do
  @moduledoc """
  Classifies transaction outputs as P2PKH, STAS, or DSTAS.

  Delegates to BsvSdk.Tokens.ScriptReader for STAS v2 script pattern matching.

  TODO: Implement classification logic in Phase 4.
  """

  @doc """
  Classifies a transaction output's script type.

  ## Parameters
    - `script_hex` — the output script in hex

  ## Returns
    `:p2pkh` | `:stas` | `:dstas` | `:unknown`
  """
  def classify(_script_hex) do
    # TODO: Delegate to BsvSdk.Tokens.ScriptReader in Phase 4
    :unknown
  end
end
