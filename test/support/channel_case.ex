defmodule ConsigliereWeb.ChannelCase do
  @moduledoc """
  Test case template for Phoenix Channel tests.

  Sets up the Ecto sandbox and imports channel test helpers.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import ConsigliereWeb.ChannelCase

      @endpoint ConsigliereWeb.Endpoint
    end
  end

  setup tags do
    Consigliere.DataCase.setup_sandbox(tags)
    :ok
  end
end
