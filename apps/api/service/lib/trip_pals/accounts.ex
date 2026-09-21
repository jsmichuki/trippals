defmodule TripPals.Accounts do
  import Ecto.Query

  alias TripPals.Accounts.AuthIdentity
  alias TripPals.Accounts.CommunityRuleAcceptance
  alias TripPals.Accounts.PasskeyCredential
  alias TripPals.Accounts.Profile
  alias TripPals.Accounts.RefreshToken
  alias TripPals.Accounts.Session
  alias TripPals.Accounts.User
  alias TripPals.Repo

  def create_user do
    Repo.transaction(fn ->
      with {:ok, user} <- Repo.insert(User.changeset(%User{}, %{})),
           {:ok, _profile} <- Repo.insert(Profile.changeset(%Profile{user_id: user.id}, %{})) do
        user
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def link_identity(user_id, provider, provider_subject) do
    %AuthIdentity{user_id: user_id}
    |> AuthIdentity.changeset(%{provider: provider, provider_subject: provider_subject})
    |> Repo.insert()
  end

  def resolve_verified_identity(provider, subject, linking_user_id \\ nil) do
    Repo.transaction(fn ->
      case Repo.get_by(AuthIdentity, provider: provider, provider_subject: subject) do
        %AuthIdentity{user_id: user_id} ->
          Repo.get!(User, user_id)

        nil when is_binary(linking_user_id) ->
          {:ok, _identity} = link_identity(linking_user_id, provider, subject)
          Repo.get!(User, linking_user_id)

        nil ->
          {:ok, user} = create_user()
          {:ok, _identity} = link_identity(user.id, provider, subject)
          user
      end
    end)
  end

  def unlink_identity(user_id, provider) do
    Repo.transaction(fn ->
      identity = Repo.get_by(AuthIdentity, user_id: user_id, provider: provider)

      cond do
        is_nil(identity) -> Repo.rollback(:not_found)
        usable_login_method_count(user_id) <= 1 -> Repo.rollback(:final_login_method)
        true -> Repo.delete!(identity)
      end
    end)
  end

  def revoke_passkey(user_id, credential_id, session_id) do
    with %Session{} = session <- Repo.get_by(Session, id: session_id, user_id: user_id),
         true <- recently_authenticated?(session) do
      Repo.transaction(fn ->
        credential = Repo.get_by(PasskeyCredential, id: credential_id, user_id: user_id)

        cond do
          is_nil(credential) ->
            Repo.rollback(:not_found)

          not is_nil(credential.revoked_at) ->
            credential

          usable_login_method_count(user_id) <= 1 ->
            Repo.rollback(:final_login_method)

          true ->
            credential |> Ecto.Changeset.change(revoked_at: DateTime.utc_now()) |> Repo.update!()
        end
      end)
    else
      _ -> {:error, :recent_auth_required}
    end
  end

  def profile_complete?(%User{} = user) do
    from(profile in Profile,
      where:
        profile.user_id == ^user.id and not is_nil(profile.profile_completed_at) and
          not is_nil(profile.adult_eligible_at),
      select: count(profile.id) > 0
    )
    |> Repo.one()
  end

  def recently_authenticated?(session, now \\ DateTime.utc_now(), max_age_seconds \\ 900)

  def recently_authenticated?(%{revoked_at: revoked_at}, _now, _max_age)
      when not is_nil(revoked_at), do: false

  def recently_authenticated?(
        %{recently_authenticated_at: authenticated_at},
        now,
        max_age_seconds
      ) do
    DateTime.diff(now, authenticated_at, :second) <= max_age_seconds
  end

  def create_session(user_id, device_id \\ nil) do
    now = DateTime.utc_now()

    %TripPals.Accounts.Session{user_id: user_id}
    |> TripPals.Accounts.Session.changeset(%{
      family_id: Ecto.UUID.generate(),
      device_id: device_id,
      recently_authenticated_at: now
    })
    |> Repo.insert()
  end

  def current_actor(session_id, user_id) do
    query =
      from(session in Session,
        join: user in User,
        on: user.id == session.user_id,
        where: session.id == ^session_id and session.user_id == ^user_id,
        where: is_nil(session.revoked_at) and user.status == "active",
        select: %{id: user.id, session_id: session.id}
      )

    case Repo.one(query) do
      nil -> {:error, :invalid_session}
      actor -> {:ok, Map.put(actor, :roles, TripPals.TrustSafety.staff_roles(actor.id))}
    end
  end

  def revoke_session(session_id, user_id) do
    now = DateTime.utc_now()

    from(session in Session, where: session.id == ^session_id and session.user_id == ^user_id)
    |> Repo.update_all(set: [revoked_at: now, updated_at: now])
    |> case do
      {1, _} -> :ok
      _ -> {:error, :not_found}
    end
  end

  def get_me(user_id) do
    from(profile in Profile, where: profile.user_id == ^user_id)
    |> Repo.one()
  end

  def update_me(user_id, attributes) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      profile = Repo.get_by!(Profile, user_id: user_id)
      adult? = attributes["adult_confirmation"] == true
      rule_version = attributes["community_rule_version"]

      profile_attributes =
        attributes
        |> Map.take(["display_name", "invitation_discoverable"])
        |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
        |> maybe_put_adult_eligible(adult?, now)

      with {:ok, profile} <- Repo.update(Profile.changeset(profile, profile_attributes)),
           :ok <- accept_rules(user_id, rule_version, now),
           {:ok, profile} <- complete_profile(profile, rule_version, now) do
        profile
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def refresh_session(raw_token) do
    with {:ok, {replacement_raw_token, replacement}} <- rotate_refresh_token(raw_token),
         %Session{} = session <- Repo.get(Session, replacement.session_id) do
      {:ok, session, replacement_raw_token}
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :invalid_refresh_token}
    end
  end

  def issue_refresh_token(%Session{} = session, expires_at \\ default_refresh_expiry()) do
    {raw_token, token_hash} = new_refresh_token()

    %RefreshToken{session_id: session.id}
    |> RefreshToken.changeset(%{token_hash: token_hash, expires_at: expires_at})
    |> Repo.insert()
    |> case do
      {:ok, refresh_token} -> {:ok, raw_token, refresh_token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def rotate_refresh_token(raw_token) when is_binary(raw_token) do
    result =
      Repo.transaction(fn ->
        token =
          from(token in RefreshToken,
            where: token.token_hash == ^hash_refresh_token(raw_token),
            lock: "FOR UPDATE",
            preload: [:session]
          )
          |> Repo.one()

        rotate_locked_token(token)
      end)

    case result do
      {:ok, {:refresh_token_reuse, family_id}} ->
        revoke_session_family!(family_id, DateTime.utc_now())
        {:error, :refresh_token_reuse}

      {:ok, {replacement_raw_token, replacement}} ->
        {:ok, {replacement_raw_token, replacement}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp rotate_locked_token(nil), do: Repo.rollback(:invalid_refresh_token)

  defp rotate_locked_token(%RefreshToken{session: session} = token) do
    now = DateTime.utc_now()

    cond do
      not is_nil(token.used_at) or not is_nil(token.revoked_at) ->
        {:refresh_token_reuse, session.family_id}

      not is_nil(session.revoked_at) ->
        Repo.rollback(:invalid_refresh_token)

      DateTime.compare(token.expires_at, now) != :gt ->
        Repo.rollback(:refresh_token_expired)

      true ->
        {raw_token, token_hash} = new_refresh_token()

        {:ok, replacement} =
          %RefreshToken{session_id: session.id}
          |> RefreshToken.changeset(%{
            token_hash: token_hash,
            expires_at: default_refresh_expiry()
          })
          |> Repo.insert()

        {:ok, _token} =
          token
          |> RefreshToken.changeset(%{used_at: now, replaced_by_id: replacement.id})
          |> Repo.update()

        {raw_token, replacement}
    end
  end

  defp revoke_session_family!(family_id, now) do
    from(session in Session,
      where: session.family_id == ^family_id and is_nil(session.revoked_at)
    )
    |> Repo.update_all(set: [revoked_at: now, updated_at: now])
  end

  defp new_refresh_token do
    raw_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    {raw_token, hash_refresh_token(raw_token)}
  end

  defp hash_refresh_token(raw_token), do: :crypto.hash(:sha256, raw_token)
  defp default_refresh_expiry, do: DateTime.add(DateTime.utc_now(), 30 * 86_400, :second)

  defp usable_login_method_count(user_id) do
    identities =
      Repo.aggregate(from(identity in AuthIdentity, where: identity.user_id == ^user_id), :count)

    passkeys =
      Repo.aggregate(
        from(credential in PasskeyCredential,
          where: credential.user_id == ^user_id and is_nil(credential.revoked_at)
        ),
        :count
      )

    identities + passkeys
  end

  defp maybe_put_adult_eligible(attributes, true, now),
    do: Map.put(attributes, :adult_eligible_at, now)

  defp maybe_put_adult_eligible(attributes, false, _now), do: attributes

  defp accept_rules(_user_id, nil, _now), do: :ok

  defp accept_rules(user_id, rule_version, now) do
    %CommunityRuleAcceptance{user_id: user_id}
    |> CommunityRuleAcceptance.changeset(%{rule_version: rule_version, accepted_at: now})
    |> Repo.insert(on_conflict: :nothing)
    |> case do
      {:ok, _acceptance} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp complete_profile(profile, rule_version, now) do
    if profile.display_name && profile.adult_eligible_at && rule_version do
      profile |> Ecto.Changeset.change(profile_completed_at: now) |> Repo.update()
    else
      {:ok, profile}
    end
  end
end
