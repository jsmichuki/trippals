defmodule TripPals.Media do
  @moduledoc """
  Owns protected-upload intent, validation, authorization, and deletion state.

  Object bytes remain in a private adapter; API projections contain opaque IDs
  and short-lived capabilities, never an object-store URL or evidence content.
  """

  import Ecto.Query

  alias TripPals.Media.MediaObject
  alias TripPals.Media.Scanner
  alias TripPals.Media.Storage
  alias TripPals.Accounts.Profile
  alias TripPals.Platform
  alias TripPals.Repo
  alias TripPals.Safety.Report

  @intent_ttl_seconds 15 * 60
  @access_ttl_seconds 5 * 60
  @avatar_replacement_grace_seconds 60 * 60
  @avatar_limits %{"image/jpeg" => 5_000_000, "image/png" => 5_000_000, "image/webp" => 5_000_000}
  @evidence_limits %{
    "image/jpeg" => 3_000_000,
    "image/png" => 3_000_000,
    "application/pdf" => 3_000_000
  }

  def create_upload_intent(actor_id, attributes, options \\ []) do
    scope = value(attributes, "scope")

    request_hash =
      options
      |> Keyword.get_lazy(:request_hash, fn -> request_hash(attributes) end)
      |> idempotency_hash()

    operation_scope = "media:#{scope || "unknown"}:intent"

    with_command(actor_id, operation_scope, options, request_hash, fn ->
      with {:ok, scope, content_type, byte_size} <- valid_intent(attributes),
           {:ok, report_id} <- scope_reference(actor_id, scope, attributes),
           {:ok, media} <- insert_intent(actor_id, scope, content_type, byte_size, report_id) do
        {:ok, intent_payload(media)}
      end
    end)
    |> add_upload_capability(actor_id)
  end

  # The local adapter is intentionally explicit: callers need a valid scoped
  # capability before bytes can be placed in the private store. In production,
  # this maps to the equivalent scoped object-store upload operation.
  def put_upload(actor_id, media_id, upload_token, content, options \\ [])

  def put_upload(actor_id, media_id, upload_token, content, options) when is_binary(content) do
    request_hash =
      options
      |> Keyword.get_lazy(:request_hash, fn -> :crypto.hash(:sha256, content) end)
      |> idempotency_hash()

    with :ok <- verify_upload_token(upload_token, actor_id, media_id) do
      with_command(actor_id, "media:#{media_id}:upload", options, request_hash, fn ->
        media = locked_media(media_id)

        with %MediaObject{} <- media,
             :ok <- owns?(media, actor_id),
             :ok <- uploadable?(media),
             :ok <- exact_size?(media, content),
             {:ok, _metadata} <- Storage.put(media.object_key, content),
             {:ok, media} <- update_lifecycle(media, %{status: "uploaded"}) do
          {:ok, media_payload(media)}
        else
          nil -> {:error, :not_found}
          {:error, reason} -> {:error, reason}
        end
      end)
    end
  end

  def put_upload(_actor_id, _media_id, _upload_token, _content, _options),
    do: {:error, :invalid_upload_content}

  def confirm_upload(actor_id, media_id, upload_token, options \\ []) do
    request_hash =
      options |> Keyword.get_lazy(:request_hash, fn -> "confirm" end) |> idempotency_hash()

    with :ok <- verify_upload_token(upload_token, actor_id, media_id) do
      confirm_command(actor_id, media_id, options, request_hash)
    end
  end

  def signed_access(actor_id, media_id) do
    with %MediaObject{} = media <- Repo.get(MediaObject, media_id),
         :ok <- available?(media),
         :ok <- access_allowed?(actor_id, media) do
      expires_at = DateTime.add(DateTime.utc_now(), @access_ttl_seconds, :second)

      {:ok,
       %{
         media_id: media.id,
         access_token: sign("media-access", actor_id, media.id, expires_at),
         expires_at: expires_at
       }}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def read_private(actor_id, media_id, access_token) do
    with :ok <- verify_access_token(access_token, actor_id, media_id),
         %MediaObject{} = media <- Repo.get(MediaObject, media_id),
         :ok <- available?(media),
         :ok <- access_allowed?(actor_id, media),
         {:ok, content} <- Storage.read(media.object_key) do
      {:ok, media.content_type, content}
    else
      nil -> {:error, :not_found}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def cleanup(now \\ DateTime.utc_now()) do
    expiring =
      from(media in MediaObject,
        where: media.status in ["intent", "uploaded"] and media.expires_at <= ^now,
        select: media.id
      )
      |> Repo.all()

    scheduled =
      from(media in MediaObject,
        where:
          media.status in ["rejected", "expired", "available"] and
            not is_nil(media.delete_after) and media.delete_after <= ^now,
        select: media.id
      )
      |> Repo.all()

    Enum.each(expiring, &expire_and_delete(&1, now))
    Enum.each(scheduled, &delete_object(&1, now, "cleanup"))
    %{expired: length(expiring), deleted: length(scheduled)}
  end

  # D11 calls this during deletion. Avatars have no retention exception; report
  # evidence remains private and retained only for the approved case period.
  def schedule_account_deletion(user_id, now \\ DateTime.utc_now()) do
    from(media in MediaObject, where: media.owner_id == ^user_id and media.scope == "avatar")
    |> Repo.update_all(set: [delete_after: now, updated_at: now])

    from(media in MediaObject,
      where: media.owner_id == ^user_id and media.scope == "report_evidence",
      where: is_nil(media.retention_until)
    )
    |> Repo.update_all(
      set: [retention_until: DateTime.add(now, 7 * 365 * 86_400, :second), updated_at: now]
    )

    :ok
  end

  defp insert_intent(actor_id, scope, content_type, byte_size, report_id) do
    id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    media = %MediaObject{owner_id: actor_id, report_id: report_id}

    attributes = %{
      id: id,
      object_key: "private/media/#{id}",
      scope: scope,
      content_type: content_type,
      byte_size: byte_size,
      expires_at: DateTime.add(now, @intent_ttl_seconds, :second),
      metadata: %{}
    }

    media
    |> MediaObject.intent_changeset(attributes)
    |> Repo.insert()
  end

  defp confirm_locked(actor_id, media_id) do
    media = locked_media(media_id)

    with %MediaObject{} <- media,
         :ok <- owns?(media, actor_id),
         :ok <- confirmable?(media),
         {:ok, content} <- Storage.read(media.object_key),
         :ok <- content_valid?(media, content),
         :clean <- Scanner.scan(content),
         {:ok, media} <-
           update_lifecycle(media, %{
             status: "available",
             validation_status: "validated",
             scan_status: "clean",
             content_sha256: :crypto.hash(:sha256, content),
             confirmed_at: DateTime.utc_now(),
             available_at: DateTime.utc_now(),
             delete_after: nil
           }),
         :ok <- reference_available_media(media) do
      {:ok, media}
    else
      nil -> {:error, :not_found}
      {:error, :enoent} -> {:error, :upload_missing}
      {:error, reason} -> reject(media, reason)
    end
  end

  defp reject(%MediaObject{} = media, reason) do
    _ = Storage.delete(media.object_key)

    case update_lifecycle(media, %{
           status: "rejected",
           validation_status: "rejected",
           scan_status: if(reason == :malware_detected, do: "failed", else: media.scan_status),
           delete_after: DateTime.utc_now(),
           deletion_reason: Atom.to_string(reason)
         }) do
      {:ok, _media} -> {:error, reason}
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp reject(nil, reason), do: {:error, reason}

  defp expire_and_delete(media_id, now) do
    Repo.transaction(fn ->
      case locked_media(media_id) do
        %MediaObject{status: status} = media when status in ["intent", "uploaded"] ->
          _ = Storage.delete(media.object_key)

          update_lifecycle(media, %{
            status: "expired",
            delete_after: now,
            deletion_reason: "intent_expired"
          })

        _ ->
          :ok
      end
    end)
  end

  defp delete_object(media_id, now, reason) do
    Repo.transaction(fn ->
      case locked_media(media_id) do
        %MediaObject{status: "deleted"} ->
          :ok

        %MediaObject{} = media ->
          _ = Storage.delete(media.object_key)
          update_lifecycle(media, %{status: "deleted", deleted_at: now, deletion_reason: reason})

        nil ->
          :ok
      end
    end)
  end

  defp reference_available_media(%MediaObject{scope: "avatar"} = media) do
    profile =
      Repo.one(
        from(profile in Profile,
          where: profile.user_id == ^media.owner_id,
          lock: "FOR UPDATE"
        )
      )

    previous_avatar_id = profile && profile.avatar_media_id

    with %Profile{} <- profile,
         {:ok, _profile} <- Repo.update(Ecto.Changeset.change(profile, avatar_media_id: media.id)) do
      schedule_replaced_avatar(previous_avatar_id, media.id)
    else
      nil -> {:error, :profile_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reference_available_media(%MediaObject{}), do: :ok

  defp schedule_replaced_avatar(previous_id, current_id) when previous_id in [nil, current_id],
    do: :ok

  defp schedule_replaced_avatar(previous_id, _current_id) do
    from(media in MediaObject,
      where: media.id == ^previous_id and media.scope == "avatar" and media.status == "available"
    )
    |> Repo.update_all(
      set: [
        delete_after: DateTime.add(DateTime.utc_now(), @avatar_replacement_grace_seconds, :second)
      ]
    )

    :ok
  end

  defp confirm_command(actor_id, media_id, options, request_hash) do
    key = Keyword.get(options, :idempotency_key)

    case Repo.transaction(fn ->
           case claim(actor_id, "media:#{media_id}:confirm", key, request_hash) do
             {:ok, :replay, claim} -> {:replay, claim.response_status, claim.response_body}
             {:ok, :in_progress, _claim} -> Repo.rollback(:idempotency_in_progress)
             {:ok, :new, claim} -> persist_confirmation(claim, actor_id, media_id)
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, {:ok, payload}} -> {:ok, payload}
      {:ok, {:error, reason}} -> {:error, reason}
      {:ok, {:replay, status, payload}} when status in 200..299 -> {:ok, normalize_map(payload)}
      {:ok, {:replay, _status, %{"error" => reason}}} -> {:error, String.to_existing_atom(reason)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_confirmation(claim, actor_id, media_id) do
    # Invalid content is committed as rejected before returning an error, so
    # cleanup can safely remove it and it can never become available on retry.
    case confirm_locked(actor_id, media_id) do
      {:ok, media} ->
        payload = media_payload(media)
        record_confirmation_result(claim, 200, payload)
        {:ok, payload}

      {:error, reason} ->
        record_confirmation_result(claim, 422, %{"error" => Atom.to_string(reason)})
        {:error, reason}
    end
  end

  defp record_confirmation_result(nil, _status, _payload), do: :ok

  defp record_confirmation_result(claim, status, payload) do
    {:ok, _claim} = Platform.record_idempotency_response(claim, status, stringify(payload))
  end

  defp with_command(actor_id, operation_scope, options, request_hash, operation) do
    key = Keyword.get(options, :idempotency_key)

    Repo.transaction(fn ->
      case claim(actor_id, operation_scope, key, request_hash) do
        {:ok, :replay, claim} ->
          claim.response_body

        {:ok, :new, claim} ->
          case operation.() do
            {:ok, payload} ->
              if claim do
                {:ok, _claim} =
                  Platform.record_idempotency_response(claim, 200, stringify(payload))
              end

              payload

            {:error, reason} ->
              Repo.rollback(reason)
          end

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp claim(_actor_id, _scope, nil, _hash), do: {:ok, :new, nil}

  defp claim(actor_id, scope, key, request_hash),
    do: Platform.claim_idempotency(actor_id, scope, key, request_hash)

  defp add_upload_capability({:ok, payload}, actor_id) when is_map(payload) do
    media_id = payload["media_id"] || payload[:media_id]

    with %MediaObject{} = media <- Repo.get(MediaObject, media_id),
         :ok <- owns?(media, actor_id),
         :ok <- uploadable?(media) do
      {:ok,
       Map.put(
         normalize_map(payload),
         :upload_token,
         sign("media-upload", actor_id, media.id, media.expires_at)
       )}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp add_upload_capability(error, _actor_id), do: error

  defp valid_intent(attributes) do
    scope = value(attributes, "scope")
    content_type = value(attributes, "content_type")
    byte_size = value(attributes, "byte_size")
    limits = limits_for(scope)

    cond do
      not is_integer(byte_size) ->
        {:error, :invalid_upload_size}

      is_nil(limits) ->
        {:error, :invalid_media_scope}

      not is_integer(Map.get(limits, content_type)) ->
        {:error, :unsupported_media_type}

      byte_size < 1 or byte_size > Map.fetch!(limits, content_type) ->
        {:error, :invalid_upload_size}

      true ->
        {:ok, scope, content_type, byte_size}
    end
  end

  defp scope_reference(_actor_id, "avatar", _attributes), do: {:ok, nil}

  defp scope_reference(actor_id, "report_evidence", attributes) do
    report_id = value(attributes, "report_id")

    case Repo.get_by(Report, id: report_id, reporter_id: actor_id) do
      %Report{} -> {:ok, report_id}
      nil -> {:error, :not_found}
    end
  end

  defp scope_reference(_actor_id, _scope, _attributes), do: {:error, :invalid_media_scope}

  defp limits_for("avatar"), do: @avatar_limits
  defp limits_for("report_evidence"), do: @evidence_limits
  defp limits_for(_), do: nil

  defp content_valid?(media, content) do
    cond do
      byte_size(content) != media.byte_size -> {:error, :invalid_upload_size}
      not signature_matches?(media.content_type, content) -> {:error, :content_signature_mismatch}
      true -> :ok
    end
  end

  defp signature_matches?("image/jpeg", <<0xFF, 0xD8, 0xFF, _::binary>>), do: true

  defp signature_matches?("image/png", <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>),
    do: true

  defp signature_matches?("image/webp", <<"RIFF", _::binary-size(4), "WEBP", _::binary>>),
    do: true

  defp signature_matches?("application/pdf", <<"%PDF-", _::binary>>), do: true
  defp signature_matches?(_, _), do: false

  defp exact_size?(media, content) do
    if byte_size(content) == media.byte_size, do: :ok, else: {:error, :invalid_upload_size}
  end

  defp uploadable?(%MediaObject{status: status, expires_at: expires_at})
       when status in ["intent", "uploaded"] do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt,
      do: :ok,
      else: {:error, :upload_intent_expired}
  end

  defp uploadable?(%MediaObject{status: "available"}), do: {:error, :upload_already_confirmed}
  defp uploadable?(_media), do: {:error, :upload_not_available}

  defp confirmable?(media), do: uploadable?(media)

  defp available?(%MediaObject{
         status: "available",
         validation_status: "validated",
         scan_status: "clean"
       }),
       do: :ok

  defp available?(_media), do: {:error, :media_not_available}

  defp owns?(%MediaObject{owner_id: owner_id}, actor_id) when owner_id == actor_id, do: :ok
  defp owns?(_media, _actor_id), do: {:error, :forbidden}

  defp access_allowed?(actor_id, %MediaObject{owner_id: actor_id}), do: :ok

  defp access_allowed?(actor_id, %MediaObject{scope: "report_evidence"}) do
    if Enum.any?(
         TripPals.TrustSafety.staff_roles(actor_id),
         &(&1 in ["moderator", "administrator"])
       ),
       do: :ok,
       else: {:error, :forbidden}
  end

  defp access_allowed?(_actor_id, _media), do: {:error, :forbidden}

  defp locked_media(media_id),
    do: Repo.one(from(media in MediaObject, where: media.id == ^media_id, lock: "FOR UPDATE"))

  defp update_lifecycle(media, attributes),
    do: media |> MediaObject.lifecycle_changeset(attributes) |> Repo.update()

  defp intent_payload(media) do
    %{
      media_id: media.id,
      scope: media.scope,
      content_type: media.content_type,
      expires_at: media.expires_at
    }
  end

  defp media_payload(media) do
    %{
      media_id: media.id,
      scope: media.scope,
      status: media.status,
      content_type: media.content_type,
      byte_size: media.byte_size
    }
  end

  defp sign(salt, actor_id, media_id, expires_at) do
    Phoenix.Token.sign(TripPalsWeb.Endpoint, salt, %{
      "actor_id" => actor_id,
      "media_id" => media_id,
      "expires_at" => DateTime.to_unix(expires_at)
    })
  end

  defp verify_upload_token(token, actor_id, media_id),
    do: verify_token(token, "media-upload", actor_id, media_id)

  defp verify_access_token(token, actor_id, media_id),
    do: verify_token(token, "media-access", actor_id, media_id)

  defp verify_token(token, salt, actor_id, media_id) when is_binary(token) do
    with {:ok, %{"actor_id" => ^actor_id, "media_id" => ^media_id, "expires_at" => expires_at}} <-
           Phoenix.Token.verify(TripPalsWeb.Endpoint, salt, token, max_age: @intent_ttl_seconds),
         true <- expires_at > DateTime.to_unix(DateTime.utc_now()) do
      :ok
    else
      _ -> {:error, :invalid_upload_capability}
    end
  end

  defp verify_token(_token, _salt, _actor_id, _media_id), do: {:error, :invalid_upload_capability}

  defp value(map, key), do: Map.get(map, key) || Map.get(map, String.to_existing_atom(key))

  defp request_hash(attributes), do: :crypto.hash(:sha256, :erlang.term_to_binary(attributes))

  defp idempotency_hash(hash) when is_binary(hash) and byte_size(hash) == 64, do: hash

  defp idempotency_hash(hash) when is_binary(hash),
    do: :crypto.hash(:sha256, hash) |> Base.encode16(case: :lower)

  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp normalize_map(map), do: Map.new(map, fn {key, value} -> {normalize_key(key), value} end)
  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key(key), do: String.to_existing_atom(key)
end
