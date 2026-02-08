class AfmApi < Formula
  desc "OpenAI-compatible local server for Apple Foundation Model"
  homepage "https://github.com/tankibaj/apple-foundation-model-api"
  url "https://github.com/tankibaj/apple-foundation-model-api/archive/refs/tags/v1.1.1.tar.gz"
  sha256 "e8b84865dc93f1aeaf0a86a9d3149254a3be3640199c6a1e1fe36bd55c7fcfa6"
  license "MIT"

  depends_on :macos

  def install
    if File.exist?("afm-api") && File.exist?("afm-api-server")
      # Binary release asset path (no local build required).
      bin.install "afm-api"
      bin.install "afm-api-server"
    else
      # Source release fallback.
      bin.install "bin/afm-api"
      pkgshare.install "Package.swift"
      pkgshare.install "Sources"
      launcher = bin/"afm-api"
      if launcher.read.include?("__AFM_API_VERSION__")
        inreplace launcher, "__AFM_API_VERSION__", version.to_s
      end
    end
  end

  test do
    assert_predicate bin/"afm-api", :exist?
    if (bin/"afm-api-server").exist?
      assert_predicate bin/"afm-api-server", :exist?
    else
      assert_predicate pkgshare/"Package.swift", :exist?
      assert_predicate pkgshare/"Sources/AFMAPI/main.swift", :exist?
    end
  end
end
