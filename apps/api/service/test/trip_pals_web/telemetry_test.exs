defmodule TripPalsWeb.TelemetryTest do
  use ExUnit.Case, async: true

  test "declares privacy-safe operational metrics for all delivery-12 signals" do
    metric_names = TripPalsWeb.Telemetry.metrics() |> Enum.map(&Enum.join(&1.name, "."))

    for metric <- [
          "trip_pals.observability.http.duration",
          "trip_pals.observability.channel.duration",
          "trip_pals.observability.job.count",
          "trip_pals.observability.rsvp.count",
          "trip_pals.observability.chat_delivery.count",
          "trip_pals.observability.push.count",
          "trip_pals.observability.lifecycle.count",
          "trip_pals.observability.rate_limit.count"
        ] do
      assert metric in metric_names
    end
  end

  test "production baseline requires database recovery and readiness alerts" do
    baseline =
      Path.expand("../../../../../infra/observability/production-baseline.yml", __DIR__)
      |> File.read!()

    assert baseline =~ "point_in_time_recovery: true"
    assert baseline =~ "cadence: monthly"
    assert baseline =~ "readiness_failure"
    assert baseline =~ "tls_required: true"
    refute baseline =~ "secret_value:"
  end
end
