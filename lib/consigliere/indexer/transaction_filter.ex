defmodule Consigliere.Indexer.TransactionFilter do
  @moduledoc """
  ETS-backed filter for checking whether a transaction involves watched
  addresses or STAS tokens. The hot path — every incoming tx hits this.

  ETS tables provide lock-free concurrent reads. Writes (admin adds/removes
  an address or token) are serialized through this GenServer.

  TODO: Implement ETS table management and matching logic in Phase 2.
  """

  use GenServer

  @addresses_table :watched_addresses
  @tokens_table :watched_tokens

  ## ── Client API ──

  @doc """
  Starts the TransactionFilter GenServer and creates ETS tables.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Adds an address to the ETS watched-addresses table.

  ## Parameters
    - `address` — BSV address string to watch

  ## Returns
    :ok
  """
  def add_address(address) do
    GenServer.call(__MODULE__, {:add_address, address})
  end

  @doc """
  Adds a token ID to the ETS watched-tokens table.

  ## Parameters
    - `token_id` — STAS token ID string to watch

  ## Returns
    :ok
  """
  def add_token(token_id) do
    GenServer.call(__MODULE__, {:add_token, token_id})
  end

  @doc """
  Checks whether a given address is in the watched set.

  ## Parameters
    - `address` — BSV address string

  ## Returns
    Boolean indicating whether the address is watched.
  """
  def watching_address?(address) do
    :ets.member(@addresses_table, address)
  end

  @doc """
  Checks whether a given token ID is in the watched set.

  ## Parameters
    - `token_id` — STAS token ID string

  ## Returns
    Boolean indicating whether the token is watched.
  """
  def watching_token?(token_id) do
    :ets.member(@tokens_table, token_id)
  end

  ## ── Server Callbacks ──

  @impl true
  def init(_opts) do
    :ets.new(@addresses_table, [:set, :public, :named_table, read_concurrency: true])
    :ets.new(@tokens_table, [:set, :public, :named_table, read_concurrency: true])

    # Load initial data from DB into ETS
    load_from_db()

    {:ok, %{}}
  end

  @impl true
  def handle_call({:add_address, address}, _from, state) do
    :ets.insert(@addresses_table, {address, true})
    {:reply, :ok, state}
  end

  def handle_call({:add_token, token_id}, _from, state) do
    :ets.insert(@tokens_table, {token_id, true})
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## ── Private Helpers ──

  # Loads all watched addresses and tokens from the database into ETS tables
  # on startup, so the filter is immediately ready for matching.
  defp load_from_db do
    alias Consigliere.Repo
    alias Consigliere.Schema.{WatchingAddress, WatchingToken}

    try do
      Repo.all(WatchingAddress)
      |> Enum.each(fn wa -> :ets.insert(@addresses_table, {wa.address, true}) end)

      Repo.all(WatchingToken)
      |> Enum.each(fn wt -> :ets.insert(@tokens_table, {wt.token_id, true}) end)
    rescue
      # DB may not be available during tests or initial setup
      _ -> :ok
    end
  end
end
