defmodule Consigliere.Services.SyncStatus do
  @moduledoc """
  Reports the chain synchronization status of the indexer.

  Compares the highest processed block against the node's chain tip.

  TODO: Implement RPC chain tip comparison in Phase 2.
  """

  alias Consigliere.Repo
  alias Consigliere.Schema.BlockProcessContext
  import Ecto.Query

  @doc """
  Returns current sync status including last processed block height.

  ## Returns
    Map with :last_block_height, :last_block_hash, :is_synced fields.
  """
  def get_status do
    last_block =
      BlockProcessContext
      |> order_by([b], desc: b.height)
      |> limit(1)
      |> Repo.one()

    case last_block do
      nil ->
        %{last_block_height: 0, last_block_hash: nil, is_synced: false}

      block ->
        %{
          last_block_height: block.height,
          last_block_hash: block.id,
          is_synced: false
        }
    end
  end
end
