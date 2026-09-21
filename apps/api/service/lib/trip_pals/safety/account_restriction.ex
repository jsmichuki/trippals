defmodule TripPals.Safety.AccountRestriction do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @kinds ~w(join_freeze chat_freeze activity_review account_suspension)

  schema "account_restrictions" do
    field :kind, :string
    field :scope, :string, default: "account"
    field :reason, :string
    field :notice, :string
    field :status, :string, default: "active"
    field :effective_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :review_at, :utc_datetime_usec
    field :lifted_at, :utc_datetime_usec
    belongs_to :user, TripPals.Accounts.User
    belongs_to :moderation_case, TripPals.Safety.ModerationCase, foreign_key: :case_id
    belongs_to :imposed_by, TripPals.Accounts.User
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(restriction, attributes) do
    restriction
    |> cast(attributes, [
      :kind,
      :scope,
      :reason,
      :notice,
      :status,
      :effective_at,
      :expires_at,
      :review_at,
      :lifted_at
    ])
    |> validate_required([:kind, :scope, :reason, :notice, :status, :effective_at])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:scope, ~w(account activity conversation))
    |> validate_inclusion(:status, ~w(active lifted under_review))
    |> validate_length(:reason, min: 3, max: 1_000)
    |> validate_length(:notice, min: 3, max: 1_000)
    |> validate_expiry()
  end

  defp validate_expiry(changeset) do
    case {get_field(changeset, :effective_at), get_field(changeset, :expires_at)} do
      {%DateTime{} = effective_at, %DateTime{} = expires_at} ->
        if DateTime.compare(expires_at, effective_at) == :gt,
          do: changeset,
          else: add_error(changeset, :expires_at, "must be after effective_at")

      _ ->
        changeset
    end
  end
end
