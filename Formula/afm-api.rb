class AfmApi < Formula
  desc "OpenAI-compatible local server for Apple Foundation Model"
  homepage "https://github.com/tankibaj/apple-foundation-model-api"
  url "https://github.com/tankibaj/apple-foundation-model-api/archive/refs/tags/v1.0.2.tar.gz"
  sha256 "5b20b82be9707c0d7f40e54d796c8466d8b7394b820cdd0e321936a9afc5cb68"
  license "MIT"

  depends_on :macos

  def install
    bin.install "bin/afm-api"
    pkgshare.install "src/afm-api.swift"

    # Make the launcher reference the Homebrew-installed Swift source path.
    inreplace bin/"afm-api", %r{\$SCRIPT_DIR/\.\./src/afm-api.swift}, "#{pkgshare}/afm-api.swift"
  end

  test do
    assert_predicate bin/"afm-api", :exist?
    assert_predicate pkgshare/"afm-api.swift", :exist?
  end
end
