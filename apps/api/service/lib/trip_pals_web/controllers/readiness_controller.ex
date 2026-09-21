defmodule TripPalsWeb.ReadinessController do
  use TripPalsWeb, :controller

  alias TripPals.Repo
  alias TripPalsWeb.API.Response

  def show(conn, _params) do
    case database_ready?() do
      true -> Response.ok(conn, %{status: "ready"})
      false -> Response.error(conn, :service_unavailable, "Service is not ready", 503)
    end
  end

  defp database_ready? do
    case Repo.query("SELECT 1", [], timeout: 1_000) do
      {:ok, _result} -> true
      {:error, _reason} -> false
    end
  rescue
    DBConnection.ConnectionError -> false
  catch
    :exit, _reason -> false
  end
end
