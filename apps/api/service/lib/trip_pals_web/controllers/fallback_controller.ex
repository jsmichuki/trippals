defmodule TripPalsWeb.FallbackController do
  use TripPalsWeb, :controller

  alias Ecto.Changeset
  alias TripPalsWeb.API.Response

  def call(conn, {:error, %Changeset{} = changeset}) do
    Response.error(conn, :validation_failed, "Validation failed", 422, field_errors(changeset))
  end

  def call(conn, {:error, :not_found}) do
    Response.error(conn, :not_found, "The requested resource was not found", 404)
  end

  def call(conn, {:error, :forbidden}) do
    Response.error(conn, :forbidden, "You do not have permission for this action", 403)
  end

  def call(conn, {:error, :unauthorized}) do
    Response.error(conn, :authentication_required, "Authentication is required", 401)
  end

  def call(conn, {:error, :conflict, current}) do
    Response.error(conn, :version_conflict, "The resource has changed", 409, nil, current)
  end

  def call(conn, {:error, code}) when is_atom(code) do
    Response.error(conn, code, "The request could not be completed", 422)
  end

  defp field_errors(changeset) do
    Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r/%{(\w+)}/, message, fn _, key ->
        options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
