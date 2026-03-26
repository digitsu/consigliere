import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/consigliere start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :consigliere, ConsigliereWeb.Endpoint, server: true
end

# Default port 5000 for drop-in compatibility with the original C# consigliere
config :consigliere, ConsigliereWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "5000"))]

# ── Consigliere: BSV network and node configuration ──
config :consigliere,
  network: System.get_env("NETWORK", "testnet"),
  bsv_node: [
    rpc_url: System.get_env("BSV_NODE_RPC_URL", "http://localhost:18332"),
    rpc_user: System.get_env("BSV_NODE_RPC_USER"),
    rpc_password: System.get_env("BSV_NODE_RPC_PASSWORD")
  ],
  zmq: [
    raw_tx: System.get_env("ZMQ_RAW_TX", "tcp://localhost:28332"),
    hash_block: System.get_env("ZMQ_HASH_BLOCK", "tcp://localhost:28332"),
    removed_from_mempool: System.get_env("ZMQ_REMOVED_MEMPOOL", "tcp://localhost:28332"),
    discarded_from_mempool: System.get_env("ZMQ_DISCARDED_MEMPOOL", "tcp://localhost:28332")
  ],
  jungle_bus: [
    enabled: System.get_env("JUNGLE_BUS_ENABLED", "false") == "true",
    url: System.get_env("JUNGLE_BUS_URL")
  ]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :consigliere, Consigliere.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :consigliere, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :consigliere, ConsigliereWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :consigliere, ConsigliereWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :consigliere, ConsigliereWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
