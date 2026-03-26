defmodule Consigliere.Application do
  @moduledoc """
  OTP Application module for Consigliere.

  Starts the full supervision tree per PRD §5:
  - Core infrastructure (Repo, PubSub, Endpoint)
  - Blockchain interaction (Network → RPC → ZMQ)
  - Indexing pipeline (Filter, Processor, UtxoManager, BlockProcessor)
  - Background workers (monitors, verifiers, syncers)
  - Infrastructure (Finch HTTP pool, JungleBus client)
  - Registry for per-connection subscription tracking
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ConsigliereWeb.Telemetry,
      Consigliere.Repo,
      {DNSCluster, query: Application.get_env(:consigliere, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Consigliere.PubSub},
      {Registry, keys: :duplicate, name: Consigliere.Subscriptions},

      # Blockchain: network config → RPC → ZMQ (:rest_for_one)
      Consigliere.Blockchain.Supervisor,

      # Indexer: filter, processor, UTXO manager, block processor (:one_for_one)
      Consigliere.Indexer.Supervisor,

      # Workers: monitors, verifiers, syncers (:one_for_one)
      Consigliere.Workers.Supervisor,

      # Infra: Finch HTTP pool, JungleBus client (:one_for_one)
      Consigliere.Infra.Supervisor,

      # Phoenix endpoint — must be last
      ConsigliereWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Consigliere.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ConsigliereWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
