defmodule Consigliere.Infra.WhatsOnChain do
  @moduledoc """
  REST client for the WhatsOnChain (WoC) API.

  Used as a fallback for transaction lookups when data is not available
  from the local BSV node.

  TODO: Implement WoC API client in Phase 7.
  """

  @doc """
  Fetches a raw transaction by txid from WhatsOnChain.

  ## Parameters
    - `txid` — transaction ID hex string

  ## Returns
    `{:ok, raw_hex}` or `{:error, reason}`
  """
  def get_raw_tx(_txid) do
    {:error, :not_implemented}
  end
end
