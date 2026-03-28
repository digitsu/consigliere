defmodule Consigliere.Workers.StasObserver do
  @moduledoc """
  Watches for STAS token attribute changes (metadata updates,
  redemption events) by subscribing to PubSub token events
  and querying the chain for relevant changes.
  """

  use GenServer
  require Logger

  alias Consigliere.Repo
  alias Consigliere.Schema.{Utxo, WatchingToken}
  import Ecto.Query

  @check_interval :timer.minutes(10)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Subscribe to all token-related PubSub events
    Phoenix.PubSub.subscribe(Consigliere.PubSub, "stas:attributes")
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_attributes, state) do
    Logger.debug("StasObserver: checking token attributes")
    check_watched_tokens()
    schedule_check()
    {:noreply, state}
  end

  def handle_info({:stas_attribute_change, data}, state) do
    Logger.info("StasObserver: attribute change detected: #{inspect(data)}")
    # Broadcast to any listeners
    Phoenix.PubSub.broadcast(
      Consigliere.PubSub,
      "token:#{data.token_id}",
      {:attribute_changed, data}
    )
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## ── Private ──

  defp schedule_check do
    Process.send_after(self(), :check_attributes, @check_interval)
  end

  defp check_watched_tokens do
    tokens = Repo.all(WatchingToken)

    Enum.each(tokens, fn token ->
      # Count current unspent UTXOs for this token
      count =
        Utxo
        |> where([u], u.token_id == ^token.token_id and u.is_spent == false)
        |> select([u], count(u.id))
        |> Repo.one()

      Logger.debug("StasObserver: token #{token.token_id} has #{count} live UTXOs")
    end)
  end
end
