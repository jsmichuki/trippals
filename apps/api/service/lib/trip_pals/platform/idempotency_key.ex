defmodule TripPals.Platform.IdempotencyKey do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "idempotency_keys" do
    field :actor_id, Ecto.UUID
    field :operation_scope, :string
    field :key, :string
    field :request_hash, :string
    field :response_status, :integer
    field :response_body, :map
    field :expires_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def claim_changeset(idempotency_key, attributes) do
    idempotency_key
    |> cast(attributes, [:actor_id, :operation_scope, :key, :request_hash, :expires_at])
    |> validate_required([:actor_id, :operation_scope, :key, :request_hash, :expires_at])
    |> validate_length(:operation_scope, min: 1, max: 255)
    |> validate_length(:key, min: 1, max: 255)
    |> validate_length(:request_hash, is: 64)
    |> unique_constraint([:actor_id, :operation_scope, :key],
      name: :idempotency_keys_actor_scope_key_index
    )
  end

  def response_changeset(idempotency_key, status, body) do
    idempotency_key
    |> change(response_status: status, response_body: body)
    |> validate_number(:response_status,
      greater_than_or_equal_to: 100,
      less_than_or_equal_to: 599
    )
    |> validate_required([:response_status, :response_body])
  end
end
