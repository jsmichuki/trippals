defmodule TripPals.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TripPalsWeb.Telemetry,
      TripPals.Repo,
      {Oban, Application.fetch_env!(:trip_pals, Oban)},
      {DNSCluster, query: Application.get_env(:trip_pals, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TripPals.PubSub},
      # Start a worker by calling: TripPals.Worker.start_link(arg)
      # {TripPals.Worker, arg},
      # Start to serve requests, typically the last entry
      TripPalsWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TripPals.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TripPalsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
