defmodule TripPals.AccessToken do
  @moduledoc false

  alias TripPals.Accounts
  alias TripPalsWeb.Endpoint

  @salt "access-token-v1"
  @max_age_seconds 900

  def issue(session) do
    Phoenix.Token.sign(Endpoint, @salt, %{session_id: session.id, user_id: session.user_id})
  end

  def verify(token) when is_binary(token) do
    with {:ok, %{session_id: session_id, user_id: user_id}} <-
           Phoenix.Token.verify(Endpoint, @salt, token, max_age: @max_age_seconds),
         {:ok, actor} <- Accounts.current_actor(session_id, user_id) do
      {:ok, actor}
    else
      _ -> {:error, :invalid_access_token}
    end
  end
end
