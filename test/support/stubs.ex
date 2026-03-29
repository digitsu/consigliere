defmodule Consigliere.Test.RpcClientStub do
  @moduledoc """
  Lightweight stub for Consigliere.Blockchain.RpcClient in tests.

  Returns canned responses so controller/channel tests don't need a live BSV node.
  """

  use GenServer

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: Consigliere.Blockchain.RpcClient)
  end

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call({:send_raw_transaction, _hex}, _from, state) do
    # Return a fake txid (sha256 of "stub")
    fake_txid = Base.encode16(:crypto.hash(:sha256, "stub"), case: :lower)
    {:reply, {:ok, fake_txid}, state}
  end

  @impl true
  def handle_call(:get_block_count, _from, state) do
    # Return a height > 0 so sync-status reports "not synced" (no blocks processed locally)
    {:reply, {:ok, 100}, state}
  end

  @impl true
  def handle_call(_msg, _from, state) do
    {:reply, {:error, :not_implemented}, state}
  end
end

defmodule Consigliere.Test.TransactionFilterStub do
  @moduledoc """
  Lightweight stub for Consigliere.Indexer.TransactionFilter in tests.

  Accepts add_address/add_token calls without needing ETS tables or DB state.
  """

  use GenServer

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: Consigliere.Indexer.TransactionFilter)
  end

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call({:add_address, _address}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:add_token, _token_id}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(_msg, _from, state) do
    {:reply, {:error, :not_implemented}, state}
  end
end
