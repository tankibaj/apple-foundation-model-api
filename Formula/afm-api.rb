class AfmApi < Formula
  desc "OpenAI-compatible local server for Apple Foundation Model"
  homepage "https://github.com/tankibaj/apple-foundation-model-api"
  url "https://github.com/tankibaj/apple-foundation-model-api/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "74db3aaa8df38559eae9d1bf00921a6a5f2958b95e989bf14910e4880e316f11"
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
