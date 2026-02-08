class AfmApi < Formula
  desc "OpenAI-compatible local server for Apple Foundation Model"
  homepage "https://github.com/tankibaj/apple-foundation-model-api"
  url "https://github.com/tankibaj/apple-foundation-model-api/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_TARBALL_SHA256"
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
