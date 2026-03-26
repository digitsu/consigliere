defmodule Consigliere.Infra.Bitails do
  @moduledoc """
  REST client for the Bitails API.

  Provides additional transaction data not available from the BSV node
  or WhatsOnChain.

  TODO: Implement Bitails API client in Phase 7.
  """

  @doc """
  Fetches transaction details from Bitails.

  ## Parameters
    - `txid` — transaction ID hex string

  ## Returns
    `{:ok, tx_data}` or `{:error, reason}`
  """
  def get_tx(_txid) do
    {:error, :not_implemented}
  end
end
