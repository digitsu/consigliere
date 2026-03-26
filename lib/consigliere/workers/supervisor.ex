defmodule Consigliere.Workers.Supervisor do
  @moduledoc """
  Supervises background worker processes with :one_for_one strategy.

  Each worker is independent — monitors, verifiers, and syncers can
  crash and restart without affecting each other.
  """

  use Supervisor

  @doc """
  Starts the workers supervisor.
  """
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      Consigliere.Workers.UnconfirmedMonitor,
      Consigliere.Workers.ChainTipVerifier,
      Consigliere.Workers.StasObserver,
      Consigliere.Workers.MissingTxSyncer
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
