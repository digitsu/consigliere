defmodule Athanor.Workers.UnconfirmedMonitor do
  @moduledoc """
  Periodically rechecks stale unconfirmed transactions to determine
  if they've been confirmed, dropped from mempool, or replaced.
  """

  use GenServer
  require Logger

  alias Athanor.Repo
  alias Athanor.Schema.MetaTransaction
  alias Athanor.Blockchain.RpcClient
  import Ecto.Query

  @check_interval :timer.minutes(5)
  @stale_threshold :timer.hours(1)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{last_check: nil}}
  end

  @impl true
  def handle_info(:check_unconfirmed, state) do
    Logger.debug("UnconfirmedMonitor: checking stale unconfirmed transactions")
    check_stale_txs()
    schedule_check()
    {:noreply, %{state | last_check: DateTime.utc_now()}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## ── Private ──

  defp schedule_check do
    Process.send_after(self(), :check_unconfirmed, @check_interval)
  end

  defp check_stale_txs do
    stale_cutoff = System.os_time(:second) - div(@stale_threshold, 1000)

    stale_txs =
      MetaTransaction
      |> where([m], m.is_confirmed == false and m.timestamp < ^stale_cutoff)
      |> limit(100)
      |> Repo.all()

    Enum.each(stale_txs, fn meta ->
      txid_hex = Base.encode16(meta.txid, case: :lower)

      case RpcClient.get_raw_transaction(txid_hex, true) do
        {:ok, %{"blockhash" => block_hash, "confirmations" => conf}} when conf > 0 ->
          # Transaction has been confirmed — update
          Logger.info("UnconfirmedMonitor: tx #{txid_hex} now confirmed")

          meta
          |> MetaTransaction.changeset(%{
            is_confirmed: true,
            block_hash: Base.decode16!(block_hash, case: :mixed)
          })
          |> Repo.update()

        {:ok, _} ->
          # Still unconfirmed — leave it
          :ok

        {:error, %{"code" => -5}} ->
          # TX not found — likely dropped from mempool
          Logger.info("UnconfirmedMonitor: tx #{txid_hex} dropped from mempool, publishing tx_deleted")

          Phoenix.PubSub.broadcast(
            Athanor.PubSub,
            "tx:#{txid_hex}",
            {:tx_deleted, %{txid: txid_hex}}
          )

        {:error, reason} ->
          Logger.warning("UnconfirmedMonitor: failed to check tx #{txid_hex}: #{inspect(reason)}")
      end
    end)
  end
end
