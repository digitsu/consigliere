ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Consigliere.Repo, :manual)

# Start stub GenServers for blockchain/indexer services not running in test
{:ok, _} = Consigliere.Test.RpcClientStub.start_link()
{:ok, _} = Consigliere.Test.TransactionFilterStub.start_link()
