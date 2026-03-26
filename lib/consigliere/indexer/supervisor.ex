defmodule Consigliere.Indexer.Supervisor do
  @moduledoc """
  Supervises core indexing processes with :one_for_one strategy.

  Each indexer component is independent — one crash doesn't cascade.
  """

  use Supervisor

  @doc """
  Starts the indexer supervisor.
  """
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      Consigliere.Indexer.TransactionFilter,
      Consigliere.Indexer.TransactionProcessor,
      Consigliere.Indexer.BlockProcessor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
