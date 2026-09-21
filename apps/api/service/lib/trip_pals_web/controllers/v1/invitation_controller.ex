defmodule TripPalsWeb.V1.InvitationController do
  use TripPalsWeb, :controller

  alias TripPals.Invitations
  alias TripPals.Invitations.Availability
  alias TripPals.Invitations.InvitationSetting
  alias TripPalsWeb.API.Response

  def settings(conn, _params),
    do: Response.ok(conn, settings_view(Invitations.get_settings(actor_id(conn))))

  def update_settings(conn, params) do
    case Invitations.update_settings(actor_id(conn), params) do
      {:ok, setting} -> Response.ok(conn, settings_view(setting))
      {:error, changeset} -> changeset_error(conn, changeset)
    end
  end

  def availabilities(conn, _params) do
    Response.ok(conn, %{
      availabilities:
        Enum.map(Invitations.list_availabilities(actor_id(conn)), &availability_view/1)
    })
  end

  def create_availability(conn, params) do
    case Invitations.create_availability(actor_id(conn), params) do
      {:ok, availability} -> Response.ok(conn, availability_view(availability), 201)
      {:error, :invitation_consent_required} -> consent_required(conn)
      {:error, changeset} -> changeset_error(conn, changeset)
    end
  end

  def update_availability(conn, %{"id" => availability_id} = params) do
    case Invitations.update_availability(actor_id(conn), availability_id, params) do
      {:ok, availability} -> Response.ok(conn, availability_view(availability))
      {:error, :not_found} -> not_found(conn)
      {:error, :invitation_consent_required} -> consent_required(conn)
      {:error, changeset} -> changeset_error(conn, changeset)
    end
  end

  def delete_availability(conn, %{"id" => availability_id}) do
    case Invitations.revoke_availability(actor_id(conn), availability_id) do
      :ok -> send_resp(conn, :no_content, "")
      {:error, :not_found} -> not_found(conn)
    end
  end

  def candidates(conn, %{"id" => activity_id} = params) do
    case Invitations.invitation_candidates(activity_id, actor_id(conn), params) do
      {:ok, candidates} -> Response.ok(conn, candidates)
      error -> invitation_error(conn, error)
    end
  end

  def send(conn, %{"id" => activity_id, "recipient_ids" => recipient_ids}) do
    case Invitations.send_invitations(activity_id, actor_id(conn), recipient_ids) do
      {:ok, result} -> Response.ok(conn, result, 201)
      error -> invitation_error(conn, error)
    end
  end

  def send(conn, _params),
    do: Response.error(conn, :invalid_recipients, "Recipients are required", 422)

  def inbox(conn, params) do
    Response.ok(conn, %{invitations: Invitations.list_invitations(actor_id(conn), params)})
  end

  def show(conn, %{"id" => invitation_id}) do
    case Invitations.get_invitation(actor_id(conn), invitation_id) do
      {:ok, invitation} -> Response.ok(conn, invitation)
      {:error, :not_found} -> not_found(conn)
    end
  end

  def decline(conn, %{"id" => invitation_id}) do
    case Invitations.decline(invitation_id, actor_id(conn)) do
      {:ok, invitation} ->
        Response.ok(conn, %{id: invitation.id, status: invitation.status})

      {:error, :not_found} ->
        not_found(conn)

      {:error, :invitation_unavailable} ->
        Response.error(conn, :invitation_unavailable, "This invitation is unavailable", 422)

      {:error, changeset} ->
        changeset_error(conn, changeset)
    end
  end

  defp actor_id(conn), do: conn.assigns.current_actor.id

  defp settings_view(%InvitationSetting{} = setting) do
    %{
      enabled: setting.enabled,
      consented_at: setting.consented_at,
      revoked_at: setting.revoked_at,
      shareable_fields: setting.shareable_fields || %{}
    }
  end

  defp availability_view(%Availability{} = availability) do
    %{
      id: availability.id,
      city_id: availability.city_id,
      role: availability.role,
      start_local_date: availability.start_local_date,
      end_local_date: availability.end_local_date,
      time_preferences: availability.time_preferences || %{},
      shareable_fields: availability.shareable_fields || %{},
      visible: availability.visible,
      expires_at: availability.expires_at
    }
  end

  defp invitation_error(conn, {:error, :not_found}), do: not_found(conn)

  defp invitation_error(conn, {:error, :activity_full}),
    do: Response.error(conn, :activity_full, "This activity is full", 409)

  defp invitation_error(conn, {:error, :host_rate_limited}),
    do:
      Response.error(conn, :invite_rate_limited, "Invitation sending is temporarily limited", 429)

  defp invitation_error(conn, {:error, :invalid_recipients}),
    do: Response.error(conn, :invalid_recipients, "Recipients are required", 422)

  defp invitation_error(conn, {:error, :invalid_limit}),
    do:
      Response.error(conn, :validation_failed, "Validation failed", 422, %{limit: ["is invalid"]})

  defp invitation_error(conn, {:error, :invitation_unavailable}),
    do:
      Response.error(
        conn,
        :invitation_unavailable,
        "Invitations are unavailable for this activity",
        403
      )

  defp invitation_error(conn, {:error, reason}) when is_atom(reason),
    do: Response.error(conn, reason, "The request could not be completed", 422)

  defp changeset_error(conn, %Ecto.Changeset{} = changeset) do
    Response.error(
      conn,
      :validation_failed,
      "Validation failed",
      422,
      Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end)
    )
  end

  defp consent_required(conn),
    do: Response.error(conn, :invitation_consent_required, "Enable invitation consent first", 422)

  defp not_found(conn),
    do: Response.error(conn, :not_found, "The requested resource was not found", 404)
end
