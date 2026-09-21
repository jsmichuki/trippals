defmodule TripPals.Activities.ActivityIdea do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "activity_ideas" do
    field :title, :string
    field :category, :string
    field :description, :string
    field :enabled, :boolean, default: true
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(activity_idea, attributes) do
    activity_idea
    |> cast(attributes, [:title, :category, :description, :enabled])
    |> validate_required([:title, :category, :description])
    |> validate_length(:title, min: 1, max: 160)
    |> validate_length(:category, min: 1, max: 80)
  end
end
