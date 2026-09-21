defmodule TripPals.Media.Storage do
  @moduledoc """
  A deliberately private local object-store adapter for development and tests.

  It accepts only server-generated object keys and never creates a public URL.
  Production can replace this module with a private object-store adapter while
  retaining the Media context's authorization boundary.
  """

  @key_prefix "private/media/"

  def put(object_key, content) when is_binary(content) do
    with :ok <- valid_key?(object_key),
         :ok <- File.mkdir_p(Path.dirname(path_for(object_key))),
         :ok <- File.write(path_for(object_key), content, [:binary]) do
      {:ok, %{byte_size: byte_size(content), sha256: :crypto.hash(:sha256, content)}}
    end
  end

  def read(object_key) do
    with :ok <- valid_key?(object_key), do: File.read(path_for(object_key))
  end

  def delete(object_key) do
    with :ok <- valid_key?(object_key) do
      case File.rm(path_for(object_key)) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        error -> error
      end
    end
  end

  def exists?(object_key) do
    valid_key?(object_key) == :ok and File.regular?(path_for(object_key))
  end

  defp valid_key?(object_key) when is_binary(object_key) do
    suffix = String.replace_prefix(object_key, @key_prefix, "")

    if object_key != suffix and suffix =~ ~r/\A[0-9a-f-]{36}\z/i,
      do: :ok,
      else: {:error, :invalid_object_key}
  end

  defp valid_key?(_), do: {:error, :invalid_object_key}

  defp root do
    Application.get_env(:trip_pals, :media_storage_root) ||
      Path.join(System.tmp_dir!(), "trip_pals_private_media")
  end

  defp path_for(object_key),
    do: Path.join(root(), String.replace_prefix(object_key, "private/", ""))
end
