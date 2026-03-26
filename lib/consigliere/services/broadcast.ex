defmodule Consigliere.Services.Broadcast do
  @moduledoc """
  Handles transaction broadcasting via the BSV node RPC.

  Records each broadcast attempt in the broadcasts table for audit trail.

  TODO: Implement actual RPC broadcast in Phase 2.
  """

  alias Consigliere.Repo
  alias Consigliere.Schema.Broadcast

  @doc """
  Broadcasts a raw transaction hex and records the attempt.

  ## Parameters
    - `raw_tx_hex` — raw transaction in hex encoding

  ## Returns
    `{:ok, broadcast}` with the created Broadcast record.
  """
  def broadcast_tx(raw_tx_hex) do
    # TODO: Compute txid from raw hex via BsvSdk, then send via RPC
    attrs = %{
      txid: "placeholder",
      hex: raw_tx_hex,
      status: "pending"
    }

    %Broadcast{}
    |> Broadcast.changeset(attrs)
    |> Repo.insert()
  end
end
