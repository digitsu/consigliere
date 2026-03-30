defmodule Athanor.Services.SyncStatus do
  @moduledoc """
  Reports the chain synchronization status of the indexer.
  Compares the highest processed block against the node's chain tip.
  """

  alias Athanor.Repo
  alias Athanor.Schema.BlockProcessContext
  alias Athanor.Blockchain.RpcClient
  import Ecto.Query

  @doc """
  Returns current sync status including last processed block height
  and comparison with the node's chain tip.

  ## Returns
    Map with :last_block_height, :last_block_hash, :node_height, :is_synced, :blocks_behind
  """
  def get_status do
    last_block =
      BlockProcessContext
      |> order_by([b], desc: b.height)
      |> limit(1)
      |> Repo.one()

    local_height =
      case last_block do
        nil -> 0
        block -> block.height
      end

    local_hash =
      case last_block do
        nil -> nil
        block -> block.id
      end

    # Try to get node chain tip
    {node_height, is_synced, blocks_behind} =
      case RpcClient.get_block_count() do
        {:ok, tip_height} ->
          behind = tip_height - local_height
          {tip_height, behind <= 1, behind}

        {:error, _} ->
          {nil, false, nil}
      end

    %{
      last_block_height: local_height,
      last_block_hash: local_hash,
      node_height: node_height,
      is_synced: is_synced,
      blocks_behind: blocks_behind,
      status: if(is_synced, do: "synced", else: "syncing")
    }
  end
end
