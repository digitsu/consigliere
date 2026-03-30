defmodule Athanor.Infra.Supervisor do
  @moduledoc """
  Supervises infrastructure services (HTTP pool, external API clients)
  with :one_for_one strategy.
  """

  use Supervisor

  @doc """
  Starts the infra supervisor.
  """
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Finch, name: Athanor.Finch},
      Athanor.Blockchain.JungleBusClient
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
