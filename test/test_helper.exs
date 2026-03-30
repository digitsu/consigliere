ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Athanor.Repo, :manual)

# Start stub GenServers for blockchain/indexer services not running in test
{:ok, _} = Athanor.Test.RpcClientStub.start_link()
{:ok, _} = Athanor.Test.TransactionFilterStub.start_link()
