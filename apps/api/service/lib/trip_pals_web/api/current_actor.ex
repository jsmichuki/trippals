defmodule TripPalsWeb.API.CurrentActor do
  @moduledoc """
  Establishes the request actor boundary. Token verification is deliberately
  delegated to the Accounts context when session authentication is introduced.
  """

  import Plug.Conn

  alias TripPals.AccessToken

  def init(options), do: options

  def call(conn, _options), do: assign(conn, :current_actor, authenticate(conn))

  defp authenticate(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, actor} <- AccessToken.verify(token) do
      actor
    else
      _ -> nil
    end
  end
end
