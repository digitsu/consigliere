defmodule AthanorWeb.ChannelCase do
  @moduledoc """
  Test case template for Phoenix Channel tests.

  Sets up the Ecto sandbox and imports channel test helpers.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import AthanorWeb.ChannelCase

      @endpoint AthanorWeb.Endpoint
    end
  end

  setup tags do
    Athanor.DataCase.setup_sandbox(tags)
    :ok
  end
end
