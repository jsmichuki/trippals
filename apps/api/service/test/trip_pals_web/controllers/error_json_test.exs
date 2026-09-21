defmodule TripPalsWeb.ErrorJSONTest do
  use TripPalsWeb.ConnCase, async: true

  test "renders 404" do
    assert TripPalsWeb.ErrorJSON.render("404.json", %{}) == %{
             error: %{code: "not_found", message: "Not Found"},
             meta: %{correlation_id: nil}
           }
  end

  test "renders 500" do
    assert TripPalsWeb.ErrorJSON.render("500.json", %{}) ==
             %{
               error: %{code: "internal_error", message: "Internal Server Error"},
               meta: %{correlation_id: nil}
             }
  end
end
