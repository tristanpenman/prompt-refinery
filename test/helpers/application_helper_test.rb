require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "favicon_path is versioned by the favicon's contents" do
    digest = Digest::SHA256.file(Rails.public_path.join("favicon.ico")).hexdigest

    assert_equal "/favicon.ico?v=#{digest.first(16)}", favicon_path
  end
end
