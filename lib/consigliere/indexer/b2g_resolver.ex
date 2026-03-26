defmodule Consigliere.Indexer.B2gResolver do
  @moduledoc """
  Back-to-Genesis resolver — walks the input chain of a STAS token output
  back to the genesis issuance transaction to verify provenance.

  Delegates heavy lifting to BsvSdk.BackToGenesis modules.

  TODO: Implement B2G chain walking in Phase 4.
  """

  @doc """
  Resolves the provenance chain for a given STAS UTXO.

  ## Parameters
    - `txid` — transaction ID containing the STAS output
    - `vout` — output index

  ## Returns
    `{:ok, provenance_chain}` or `{:error, reason}`
  """
  def resolve(_txid, _vout) do
    # TODO: Implement in Phase 4
    {:error, :not_implemented}
  end
end
