defmodule TripPalsWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  alias TripPals.Observability

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    attach_safe_log_handlers()

    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://telemetry-metrics.hexdocs.pm
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Operational events are emitted only through TripPals.Observability,
      # which allow-lists metadata and excludes request/user payloads.
      summary("trip_pals.observability.http.duration",
        tags: [:route, :status_code],
        unit: {:native, :millisecond}
      ),
      summary("trip_pals.observability.channel.duration",
        tags: [:event, :outcome],
        unit: {:native, :millisecond}
      ),
      counter("trip_pals.observability.job.count", tags: [:queue, :outcome]),
      counter("trip_pals.observability.rsvp.count", tags: [:outcome, :conflict_type]),
      counter("trip_pals.observability.chat_delivery.count", tags: [:outcome]),
      counter("trip_pals.observability.push.count", tags: [:provider, :response_class]),
      counter("trip_pals.observability.lifecycle.count", tags: [:transition]),
      counter("trip_pals.observability.rate_limit.count", tags: [:operation, :outcome]),

      # Database Metrics
      summary("trip_pals.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("trip_pals.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("trip_pals.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("trip_pals.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("trip_pals.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {TripPalsWeb, :count_users, []}
    ]
  end

  defp attach_safe_log_handlers do
    :telemetry.detach({__MODULE__, :safe_log_handlers})

    :telemetry.attach_many(
      {__MODULE__, :safe_log_handlers},
      [
        [:phoenix, :endpoint, :stop],
        [:phoenix, :endpoint, :exception],
        [:phoenix, :channel_handled_in, :stop],
        [:phoenix, :channel_handled_in, :exception],
        [:oban, :job, :stop],
        [:oban, :job, :exception]
      ],
      &__MODULE__.handle_telemetry_event/4,
      nil
    )
  end

  @doc false
  def handle_telemetry_event([:phoenix, :endpoint, outcome], measurements, metadata, _config) do
    conn = Map.get(metadata, :conn)

    Observability.emit("http", %{duration: Map.get(measurements, :duration, 0)}, %{
      route: route(conn),
      status_code: status(conn),
      outcome: Atom.to_string(outcome),
      correlation_id: correlation_id(conn)
    })
  end

  def handle_telemetry_event(
        [:phoenix, :channel_handled_in, outcome],
        measurements,
        metadata,
        _config
      ) do
    Observability.emit("channel", %{duration: Map.get(measurements, :duration, 0)}, %{
      event: Map.get(metadata, :event),
      outcome: Atom.to_string(outcome)
    })
  end

  def handle_telemetry_event([:oban, :job, outcome], _measurements, metadata, _config) do
    job = Map.get(metadata, :job)

    Observability.emit("job", %{count: 1}, %{
      queue: if(is_map(job), do: Map.get(job, :queue), else: nil),
      outcome: Atom.to_string(outcome),
      worker: if(is_map(job), do: Map.get(job, :worker), else: nil)
    })
  end

  def handle_telemetry_event(_event, _measurements, _metadata, _config), do: :ok

  defp route(%Plug.Conn{} = conn), do: conn.private[:phoenix_route] || "unmatched"
  defp route(_conn), do: "unavailable"
  defp status(%Plug.Conn{} = conn), do: conn.status || 500
  defp status(_conn), do: 500
  defp correlation_id(%Plug.Conn{} = conn), do: conn.assigns[:correlation_id]
  defp correlation_id(_conn), do: nil
end
