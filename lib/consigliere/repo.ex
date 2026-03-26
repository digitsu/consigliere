defmodule Consigliere.Repo do
  use Ecto.Repo,
    otp_app: :consigliere,
    adapter: Ecto.Adapters.Postgres
end
