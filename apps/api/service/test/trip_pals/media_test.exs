defmodule TripPals.MediaTest do
  use TripPals.DataCase, async: false

  alias Ecto.Changeset
  alias TripPals.Accounts
  alias TripPals.Media
  alias TripPals.Media.MediaObject
  alias TripPals.Media.Storage
  alias TripPals.MediaCleanup
  alias TripPals.Repo
  alias TripPals.TrustSafety

  test "an avatar becomes readable only after scoped upload, signature validation, and a clean scan" do
    user = user()
    content = jpeg()

    assert {:ok, intent} =
             Media.create_upload_intent(
               user.id,
               %{
                 "scope" => "avatar",
                 "content_type" => "image/jpeg",
                 "byte_size" => byte_size(content)
               },
               idempotency_key: "avatar-intent",
               request_hash: "avatar-v1"
             )

    assert {:error, :media_not_available} = Media.signed_access(user.id, intent.media_id)

    assert {:ok, %{status: "uploaded"}} =
             Media.put_upload(user.id, intent.media_id, intent.upload_token, content,
               idempotency_key: "avatar-upload",
               request_hash: "upload-v1"
             )

    assert {:ok, %{status: "available"}} =
             Media.confirm_upload(user.id, intent.media_id, intent.upload_token,
               idempotency_key: "avatar-confirm",
               request_hash: "confirm-v1"
             )

    assert Accounts.get_me(user.id).avatar_media_id == intent.media_id
    assert {:ok, access} = Media.signed_access(user.id, intent.media_id)

    assert {:ok, "image/jpeg", ^content} =
             Media.read_private(user.id, intent.media_id, access.access_token)
  end

  test "private objects deny a different user even with a signed capability" do
    owner = user()
    other = user()
    media = available_avatar(owner)

    assert {:ok, access} = Media.signed_access(owner.id, media.id)

    assert {:error, :invalid_upload_capability} =
             Media.read_private(other.id, media.id, access.access_token)

    assert {:error, :forbidden} = Media.signed_access(other.id, media.id)
  end

  test "a mismatched MIME signature is rejected and its private bytes are removed" do
    user = user()
    content = jpeg()

    assert {:ok, intent} =
             Media.create_upload_intent(user.id, %{
               "scope" => "avatar",
               "content_type" => "image/png",
               "byte_size" => byte_size(content)
             })

    assert {:ok, _} = Media.put_upload(user.id, intent.media_id, intent.upload_token, content)

    assert {:error, :content_signature_mismatch} =
             Media.confirm_upload(user.id, intent.media_id, intent.upload_token)

    media = Repo.get!(MediaObject, intent.media_id)
    assert media.status == "rejected"
    refute Storage.exists?(media.object_key)
    assert {:error, :media_not_available} = Media.signed_access(user.id, media.id)
  end

  test "declared size and report ownership are enforced before a private object is accepted" do
    owner = user()
    other = user()
    content = jpeg()
    intent = avatar_intent(owner, content)

    assert {:error, :invalid_upload_size} =
             Media.put_upload(owner.id, intent.media_id, intent.upload_token, content <> "extra")

    assert {:ok, %{report_id: report_id}} =
             TrustSafety.submit_report(owner.id, %{
               "target_type" => "account",
               "target_id" => other.id,
               "reason_code" => "other"
             })

    assert {:error, :not_found} =
             Media.create_upload_intent(other.id, %{
               "scope" => "report_evidence",
               "report_id" => report_id,
               "content_type" => "application/pdf",
               "byte_size" => byte_size("%PDF-1.7")
             })
  end

  test "report evidence is stricter, malware-scanned, and is never included in a public projection" do
    reporter = user()
    target = user()

    assert {:ok, %{report_id: report_id}} =
             TrustSafety.submit_report(reporter.id, %{
               "target_type" => "account",
               "target_id" => target.id,
               "reason_code" => "other"
             })

    content = "%PDF-1.7 EICAR-STANDARD-ANTIVIRUS-TEST-FILE"

    assert {:ok, intent} =
             Media.create_upload_intent(reporter.id, %{
               "scope" => "report_evidence",
               "report_id" => report_id,
               "content_type" => "application/pdf",
               "byte_size" => byte_size(content)
             })

    assert {:ok, _} = Media.put_upload(reporter.id, intent.media_id, intent.upload_token, content)

    assert {:error, :malware_detected} =
             Media.confirm_upload(reporter.id, intent.media_id, intent.upload_token)

    media = Repo.get!(MediaObject, intent.media_id)
    assert media.status == "rejected"
    refute Map.has_key?(%{media_id: media.id, status: media.status}, :url)
    refute Map.has_key?(%{media_id: media.id, status: media.status}, :evidence)
  end

  test "expired, rejected, and account-deletion media is eligible for private cleanup" do
    user = user()
    expired = avatar_intent(user, jpeg())
    rejected = rejected_avatar(user)
    retained_evidence = report_evidence(user)

    expired_record = Repo.get!(MediaObject, expired.media_id)

    {:ok, _} =
      Repo.update(
        Changeset.change(expired_record,
          expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
        )
      )

    assert {:error, :upload_intent_expired} =
             Media.put_upload(user.id, expired.media_id, expired.upload_token, jpeg())

    assert %{expired: 1} = MediaCleanup.run()
    refute Storage.exists?(expired_record.object_key)

    assert %{deleted: deleted} = MediaCleanup.run()
    assert deleted >= 1
    assert Repo.get!(MediaObject, rejected.id).status == "deleted"

    assert :ok = Media.schedule_account_deletion(user.id)
    assert Repo.get!(MediaObject, retained_evidence.id).retention_until
  end

  test "intent and confirmation replay through the persisted idempotency result" do
    user = user()
    content = jpeg()

    attrs = %{
      "scope" => "avatar",
      "content_type" => "image/jpeg",
      "byte_size" => byte_size(content)
    }

    assert {:ok, first} =
             Media.create_upload_intent(user.id, attrs,
               idempotency_key: "same-intent",
               request_hash: "intent-hash"
             )

    assert {:ok, replay} =
             Media.create_upload_intent(user.id, attrs,
               idempotency_key: "same-intent",
               request_hash: "intent-hash"
             )

    assert first.media_id == replay.media_id
    assert {:ok, _} = Media.put_upload(user.id, first.media_id, first.upload_token, content)

    assert {:ok, first_confirmation} =
             Media.confirm_upload(user.id, first.media_id, first.upload_token,
               idempotency_key: "same-confirm",
               request_hash: "confirm-hash"
             )

    assert {:ok, replay_confirmation} =
             Media.confirm_upload(user.id, first.media_id, first.upload_token,
               idempotency_key: "same-confirm",
               request_hash: "confirm-hash"
             )

    assert first_confirmation.media_id == replay_confirmation.media_id

    assert {:error, :idempotency_key_reused} =
             Media.create_upload_intent(
               user.id,
               Map.put(attrs, "byte_size", byte_size(content) + 1),
               idempotency_key: "same-intent",
               request_hash: "different-hash"
             )
  end

  defp available_avatar(user) do
    intent = avatar_intent(user, jpeg())
    assert {:ok, _} = Media.put_upload(user.id, intent.media_id, intent.upload_token, jpeg())
    assert {:ok, _} = Media.confirm_upload(user.id, intent.media_id, intent.upload_token)
    Repo.get!(MediaObject, intent.media_id)
  end

  defp rejected_avatar(user) do
    content = jpeg()

    assert {:ok, intent} =
             Media.create_upload_intent(user.id, %{
               "scope" => "avatar",
               "content_type" => "image/png",
               "byte_size" => byte_size(content)
             })

    assert {:ok, _} = Media.put_upload(user.id, intent.media_id, intent.upload_token, content)

    assert {:error, :content_signature_mismatch} =
             Media.confirm_upload(user.id, intent.media_id, intent.upload_token)

    Repo.get!(MediaObject, intent.media_id)
  end

  defp report_evidence(reporter) do
    target = user()

    assert {:ok, %{report_id: report_id}} =
             TrustSafety.submit_report(reporter.id, %{
               "target_type" => "account",
               "target_id" => target.id,
               "reason_code" => "other"
             })

    content = "%PDF-1.7 clean"

    assert {:ok, intent} =
             Media.create_upload_intent(reporter.id, %{
               "scope" => "report_evidence",
               "report_id" => report_id,
               "content_type" => "application/pdf",
               "byte_size" => byte_size(content)
             })

    assert {:ok, _} = Media.put_upload(reporter.id, intent.media_id, intent.upload_token, content)
    assert {:ok, _} = Media.confirm_upload(reporter.id, intent.media_id, intent.upload_token)
    Repo.get!(MediaObject, intent.media_id)
  end

  defp avatar_intent(user, content) do
    assert {:ok, intent} =
             Media.create_upload_intent(user.id, %{
               "scope" => "avatar",
               "content_type" => "image/jpeg",
               "byte_size" => byte_size(content)
             })

    intent
  end

  defp user do
    assert {:ok, user} = Accounts.create_user()
    user
  end

  defp jpeg, do: <<0xFF, 0xD8, 0xFF, 1, 2, 3, 4, 5>>
end
