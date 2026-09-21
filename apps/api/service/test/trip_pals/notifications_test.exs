defmodule TripPals.NotificationsTest do
  use TripPals.DataCase, async: false
  use Oban.Testing, repo: TripPals.Repo

  alias TripPals.Accounts
  alias TripPals.Activities
  alias TripPals.Activities.Activity
  alias TripPals.Cities.City
  alias TripPals.Notifications
  alias TripPals.Notifications.Device
  alias TripPals.Notifications.Notification
  alias TripPals.Notifications.NotificationDelivery
  alias TripPals.Platform.OutboxEvent
  alias TripPals.Repo
  alias TripPals.Workers.OutboxDispatch
  alias TripPals.Workers.PushDelivery
  alias TripPals.Workers.ActivityLifecycleSweep
  alias TripPals.Workers.HostConfirmationReminder

  @hash String.duplicate("a", 64)

  setup do
    {:ok, user} = Accounts.create_user()
    %{user: user}
  end

  test "in-app notification and outbox event commit together and payload is minimal", %{
    user: user
  } do
    assert {:error, :rollback} =
             Repo.transaction(fn ->
               assert {:ok, _notification} =
                        Notifications.insert_notification(notification_attrs(user.id))

               Repo.rollback(:rollback)
             end)

    assert Repo.aggregate(Notification, :count) == 0
    assert Repo.aggregate(OutboxEvent, :count) == 0

    assert {:ok, notification} = Notifications.notify(notification_attrs(user.id))
    assert notification.id
    assert Repo.aggregate(OutboxEvent, :count) == 1

    assert %{payload: %{"activity_id" => "activity-1"}} =
             Notifications.notification_view(notification)
  end

  test "device registrations are idempotent and never return the token", %{user: user} do
    attrs = %{"platform" => "ios", "token" => "a-very-private-device-token"}

    assert {:ok, first} = Notifications.register_device(user.id, attrs, "device-key", @hash)
    assert {:ok, replay} = Notifications.register_device(user.id, attrs, "device-key", @hash)
    first_id = Map.get(first, :id) || Map.fetch!(first, "id")
    assert first_id
    replay_id = Map.get(replay, :id) || Map.fetch!(replay, "id")
    assert replay_id == first_id
    refute Map.has_key?(first, :token)
    refute Map.has_key?(first, "token")
    assert Repo.aggregate(Device, :count) == 1

    assert {:error, :idempotency_key_reused} =
             Notifications.register_device(
               user.id,
               attrs,
               "device-key",
               String.duplicate("b", 64)
             )
  end

  test "muted nonessential notifications remain in-app but do not create a push delivery", %{
    user: user
  } do
    assert {:ok, _device} =
             Notifications.register_device(
               user.id,
               %{"platform" => "android", "token" => "another-private-token"},
               "device-android",
               @hash
             )

    assert {:ok, _preference} =
             Notifications.update_preferences(
               user.id,
               %{"nonessential_enabled" => false},
               "preferences-1",
               @hash
             )

    assert {:ok, muted} = Notifications.notify(notification_attrs(user.id))

    assert {:ok, %{deliveries: 0}} = Notifications.prepare_push_deliveries(muted.id)
    assert Repo.aggregate(NotificationDelivery, :count) == 0

    assert {:ok, essential} =
             Notifications.notify(
               Map.merge(notification_attrs(user.id), %{
                 essential: true,
                 dedupe_key: "essential-notification"
               })
             )

    assert {:ok, %{deliveries: 1}} = Notifications.prepare_push_deliveries(essential.id)
    assert Repo.aggregate(NotificationDelivery, :count) == 1
  end

  test "outbox and push workers are retry-safe and invalid token marks a device invalid", %{
    user: user
  } do
    assert {:ok, _device} =
             Notifications.register_device(
               user.id,
               %{"platform" => "ios", "token" => "private-push-token"},
               "device-push",
               @hash
             )

    assert {:ok, notification} = Notifications.notify(notification_attrs(user.id))
    event = Repo.get_by!(OutboxEvent, aggregate_id: notification.id)

    assert :ok = perform_job(OutboxDispatch, %{"event_id" => event.id})
    assert :ok = perform_job(OutboxDispatch, %{"event_id" => event.id})
    assert %OutboxEvent{status: "dispatched", attempt_count: 1} = Repo.get!(OutboxEvent, event.id)

    delivery = Repo.one!(NotificationDelivery)
    Application.put_env(:trip_pals, :push_gateway, TripPals.TestSupport.InvalidPushGateway)
    on_exit(fn -> Application.delete_env(:trip_pals, :push_gateway) end)

    assert :ok = perform_job(PushDelivery, %{"delivery_id" => delivery.id})
    assert %Device{status: "invalidated"} = Repo.get!(Device, delivery.device_id)

    assert %NotificationDelivery{status: "invalidated"} =
             Repo.get!(NotificationDelivery, delivery.id)
  end

  test "notification cursor resumes without duplicate records", %{user: user} do
    assert {:ok, _} =
             Notifications.notify(Map.put(notification_attrs(user.id), :dedupe_key, "one"))

    assert {:ok, _} =
             Notifications.notify(Map.put(notification_attrs(user.id), :dedupe_key, "two"))

    assert {:ok, %{notifications: [first], next_cursor: cursor}} =
             Notifications.list_notifications(user.id, %{"limit" => "1"})

    assert is_binary(cursor)

    assert {:ok, %{notifications: [second], next_cursor: nil}} =
             Notifications.list_notifications(user.id, %{"limit" => "1", "cursor" => cursor})

    refute first.id == second.id
  end

  test "a transient push failure remains retryable and never claims delivery", %{user: user} do
    assert {:ok, _device} =
             Notifications.register_device(
               user.id,
               %{"platform" => "ios", "token" => "retryable-private-token"},
               "device-retry",
               @hash
             )

    assert {:ok, notification} = Notifications.notify(notification_attrs(user.id))
    assert {:ok, %{deliveries: 1}} = Notifications.prepare_push_deliveries(notification.id)
    delivery = Repo.one!(NotificationDelivery)

    Application.put_env(:trip_pals, :push_gateway, TripPals.TestSupport.TransientPushGateway)
    on_exit(fn -> Application.delete_env(:trip_pals, :push_gateway) end)

    assert {:error, :provider_unavailable} =
             perform_job(PushDelivery, %{"delivery_id" => delivery.id})

    assert %NotificationDelivery{
             status: "pending",
             attempt_count: 1,
             last_error_code: "provider_unavailable"
           } = Repo.get!(NotificationDelivery, delivery.id)
  end

  test "lifecycle workers create explanatory host state without inferring completion", %{
    user: user
  } do
    {:ok, _profile} =
      Accounts.update_me(user.id, %{
        "display_name" => "Lifecycle host",
        "adult_confirmation" => true,
        "community_rule_version" => "v1"
      })

    city =
      %City{}
      |> City.changeset(%{
        name: "Lifecycle #{System.unique_integer([:positive])}",
        country: "Kenya",
        iana_timezone: "Africa/Nairobi",
        launch_status: "supported"
      })
      |> Repo.insert!()

    activity = published_activity(user, city)

    activity
    |> Ecto.Changeset.change(
      confirmation_deadline_at: DateTime.add(DateTime.utc_now(), -1, :second),
      start_at: DateTime.add(DateTime.utc_now(), -7_201, :second),
      end_at: DateTime.add(DateTime.utc_now(), -1, :second)
    )
    |> Repo.update!()

    assert :ok = perform_job(HostConfirmationReminder, %{})
    assert :ok = perform_job(ActivityLifecycleSweep, %{})
    assert %Activity{status: "published"} = Repo.get!(Activity, activity.id)

    assert Repo.aggregate(Notification, :count) == 2
    assert :ok = perform_job(HostConfirmationReminder, %{})
    assert Repo.aggregate(Notification, :count) == 2
  end

  defp notification_attrs(user_id) do
    %{
      user_id: user_id,
      event_type: "activity.material_changed",
      essential: false,
      deep_link: "/activities/activity-1",
      dedupe_key: "change-#{System.unique_integer([:positive])}",
      payload: %{
        activity_id: "activity-1",
        body: "never persisted in a notification payload",
        participant_meeting_details: "never persisted"
      }
    }
  end

  defp published_activity(user, city) do
    start_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

    {:ok, draft} =
      Activities.create_draft(user.id, %{
        "city_id" => city.id,
        "title" => "Lifecycle activity",
        "category" => "culture",
        "description" => "A safe public activity",
        "start_at" => DateTime.to_iso8601(start_at),
        "end_at" => DateTime.to_iso8601(DateTime.add(start_at, 7_200, :second)),
        "iana_timezone" => city.iana_timezone,
        "public_area" => "City centre",
        "participant_meeting_details" => "Private entrance",
        "cost_amount" => "10.00",
        "currency" => "KES",
        "capacity_total" => 2
      })

    {:ok, activity} = Activities.publish(draft.id, user.id)
    activity
  end
end
