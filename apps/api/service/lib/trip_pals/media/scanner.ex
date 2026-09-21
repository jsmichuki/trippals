defmodule TripPals.Media.Scanner do
  @moduledoc false

  # This adapter provides a deterministic development/test safety gate. A
  # production adapter must invoke the selected malware scanner before returning
  # `:clean`; callers never mark content available until that result exists.
  def scan(content) when is_binary(content) do
    if String.contains?(content, "EICAR-STANDARD-ANTIVIRUS-TEST-FILE") do
      {:error, :malware_detected}
    else
      :clean
    end
  end
end
