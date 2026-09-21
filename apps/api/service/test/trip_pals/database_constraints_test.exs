defmodule TripPals.DatabaseConstraintsTest do
  use TripPals.DataCase, async: true

  alias TripPals.Identifiers
  alias TripPals.Platform.IdempotencyKey
  alias TripPals.Repo

  test "serializes product identifiers as opaque UUID strings" do
    uuid = Ecto.UUID.generate()
    assert Identifiers.public_id!(uuid) == uuid
    assert_raise ArgumentError, fn -> Identifiers.public_id!("17") end
  end

  test "database rejects an incomplete idempotency response pair" do
    attributes = %{
      actor_id: Ecto.UUID.generate(),
      operation_scope: "activity:join",
      key: "idempotency-key",
      request_hash: String.duplicate("a", 64),
      expires_at: DateTime.add(DateTime.utc_now(), 60, :second),
      response_status: 201
    }

    assert_raise Ecto.ConstraintError, fn -> Repo.insert!(struct(IdempotencyKey, attributes)) end
  end

  test "critical idempotency lookup uses its unique index" do
    {:ok, actor_id} = Ecto.UUID.dump(Ecto.UUID.generate())
    Repo.query!("SET LOCAL enable_seqscan = off")

    plan =
      Repo.query!(
        "EXPLAIN SELECT * FROM idempotency_keys WHERE actor_id = $1 AND operation_scope = $2 AND key = $3",
        [
          actor_id,
          "activity:join",
          "key"
        ]
      )

    assert plan.rows |> Enum.map_join("\n", fn [line] -> line end) =~
             "idempotency_keys_actor_scope_key_index"
  end

  test "public discovery and text search use PostgreSQL indexes" do
    {:ok, city_id} = Ecto.UUID.dump(Ecto.UUID.generate())
    Repo.query!("SET LOCAL enable_seqscan = off")

    discovery_plan =
      Repo.query!(
        """
        EXPLAIN SELECT * FROM activities
        WHERE city_id = $1
          AND status IN ('published', 'host_confirmed')
          AND start_at >= now()
        ORDER BY start_at
        """,
        [city_id]
      )

    assert plan_text(discovery_plan) =~ "activities_public_discovery_index"

    search_plan =
      Repo.query!(
        "EXPLAIN SELECT * FROM activities WHERE search_document @@ plainto_tsquery('simple', 'gallery')"
      )

    assert plan_text(search_plan) =~ "activities_search_document_index"
  end

  test "migrations use reversible change callbacks" do
    migration_directory = Path.expand("../../priv/repo/migrations", __DIR__)

    migration_directory
    |> File.ls!()
    |> Enum.reject(&String.starts_with?(&1, "."))
    |> Enum.each(fn filename ->
      assert File.read!(Path.join(migration_directory, filename)) =~ "def change do"
    end)
  end

  defp plan_text(plan), do: plan.rows |> Enum.map_join("\n", fn [line] -> line end)
end
