defmodule TripPalsWeb.V1.ConversationControllerTest do
  use TripPalsWeb.ConnCase, async: true

  alias TripPals.AccessToken
  alias TripPals.Accounts
  alias TripPals.Activities
  alias TripPals.Cities.City
  alias TripPals.Conversations.Conversation
  alias TripPals.Participation
  alias TripPals.Repo

  test "HTTP fallback requires membership and idempotency, then resumes message history" do
    {:ok, host} = host()
    {:ok, member} = Accounts.create_user()
    {:ok, session} = Accounts.create_session(member.id, "conversation-http")
    city = city()
    activity = published_activity(host, city)
    assert {:ok, _} = Participation.join(activity.id, member.id)
    conversation = Repo.get_by!(Conversation, activity_id: activity.id)
    client_message_id = Ecto.UUID.generate()

    unauthenticated = post(build_conn(), "/v1/conversations/#{conversation.id}/messages", %{})

    assert %{"error" => %{"code" => "authentication_required"}} =
             json_response(unauthenticated, 401)

    missing_key =
      build_conn()
      |> put_req_header("authorization", "Bearer #{AccessToken.issue(session)}")
      |> post("/v1/conversations/#{conversation.id}/messages", %{
        "client_message_id" => client_message_id,
        "body" => "HTTP fallback"
      })

    assert %{"error" => %{"code" => "idempotency_key_required"}} = json_response(missing_key, 400)

    created =
      build_conn()
      |> put_req_header("authorization", "Bearer #{AccessToken.issue(session)}")
      |> put_req_header("idempotency-key", "conversation-http-1")
      |> post("/v1/conversations/#{conversation.id}/messages", %{
        "client_message_id" => client_message_id,
        "body" => "HTTP fallback"
      })

    assert %{"data" => %{"id" => message_id, "sequence" => 1, "body" => "HTTP fallback"}} =
             json_response(created, 201)

    history =
      build_conn()
      |> put_req_header("authorization", "Bearer #{AccessToken.issue(session)}")
      |> get("/v1/conversations/#{conversation.id}/messages")

    assert %{"data" => %{"messages" => [%{"id" => ^message_id, "sequence" => 1}]}} =
             json_response(history, 200)
  end

  defp host do
    with {:ok, host} <- Accounts.create_user(),
         {:ok, _profile} <-
           Accounts.update_me(host.id, %{
             "display_name" => "HTTP host",
             "adult_confirmation" => true,
             "community_rule_version" => "v1"
           }) do
      {:ok, host}
    end
  end

  defp city do
    %City{}
    |> City.changeset(%{
      name: "Nairobi #{System.unique_integer([:positive])}",
      country: "Kenya",
      iana_timezone: "Africa/Nairobi",
      launch_status: "supported"
    })
    |> Repo.insert!()
  end

  defp published_activity(host, city) do
    start_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

    {:ok, draft} =
      Activities.create_draft(host.id, %{
        "city_id" => city.id,
        "title" => "HTTP walk",
        "category" => "culture",
        "description" => "A public daytime activity",
        "start_at" => DateTime.to_iso8601(start_at),
        "end_at" => DateTime.to_iso8601(DateTime.add(start_at, 7_200, :second)),
        "iana_timezone" => city.iana_timezone,
        "public_area" => "City centre",
        "participant_meeting_details" => "Private entrance",
        "cost_amount" => "10.00",
        "currency" => "KES",
        "capacity_total" => 4
      })

    {:ok, activity} = Activities.publish(draft.id, host.id)
    activity
  end
end
