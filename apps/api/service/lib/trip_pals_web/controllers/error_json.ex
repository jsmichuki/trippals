defmodule TripPalsWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  def render(template, _assigns) do
    status = template |> String.replace_suffix(".json", "") |> String.to_integer()

    %{
      error: %{
        code: error_code(status),
        message: Phoenix.Controller.status_message_from_template(template)
      },
      meta: %{correlation_id: nil}
    }
  end

  defp error_code(404), do: "not_found"
  defp error_code(405), do: "method_not_allowed"
  defp error_code(413), do: "payload_too_large"
  defp error_code(_status), do: "internal_error"
end
