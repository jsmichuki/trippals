defmodule TripPalsWeb.V1.SafetyController do
  use TripPalsWeb, :controller

  alias TripPals.TrustSafety
  alias TripPalsWeb.API.Response

  def create_report(conn, params) do
    case TrustSafety.submit_report(conn.assigns.current_actor.id, params) do
      {:ok, result} -> Response.ok(conn, result, 201)
      {:error, error} -> safety_error(conn, error)
    end
  end

  def block(conn, %{"user_id" => user_id} = params) do
    case TrustSafety.block(conn.assigns.current_actor.id, user_id, params) do
      {:ok, result} -> Response.ok(conn, result)
      {:error, error} -> safety_error(conn, error)
    end
  end

  def unblock(conn, %{"user_id" => user_id}) do
    case TrustSafety.unblock(conn.assigns.current_actor.id, user_id) do
      {:ok, result} -> Response.ok(conn, result)
      {:error, error} -> safety_error(conn, error)
    end
  end

  def restrictions(conn, _params),
    do:
      Response.ok(conn, %{
        restrictions: TrustSafety.my_restrictions(conn.assigns.current_actor.id)
      })

  def create_appeal(conn, %{"restriction_id" => restriction_id} = params) do
    case TrustSafety.submit_appeal(conn.assigns.current_actor.id, restriction_id, params) do
      {:ok, result} -> Response.ok(conn, result, 201)
      {:error, error} -> safety_error(conn, error)
    end
  end

  defp safety_error(conn, {:error, :not_found}),
    do: Response.error(conn, :not_found, "The requested resource was not found", 404)

  defp safety_error(conn, {:error, :cannot_block_self}),
    do: Response.error(conn, :cannot_block_self, "You cannot block yourself", 422)

  defp safety_error(conn, {:error, :appeal_not_available}),
    do: Response.error(conn, :appeal_not_available, "An appeal is not available", 422)

  defp safety_error(conn, {:error, :reason_required}),
    do: Response.error(conn, :reason_required, "A reason is required", 422)

  defp safety_error(conn, {:error, %Ecto.Changeset{} = changeset}),
    do:
      Response.error(
        conn,
        :validation_failed,
        "Validation failed",
        422,
        Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end)
      )

  defp safety_error(conn, {:error, _}),
    do: Response.error(conn, :safety_request_failed, "The request could not be completed", 422)
end
