# Homebrew formula for Răboj. Lives in the tap repo MIKALAKE/homebrew-tap as Formula/raboj.rb
# once the project is public. It builds from source on the user's Mac with the Command Line Tools,
# so the app is not quarantined and macOS shows no warning. No Apple Developer account involved.
#
# Release checklist: update `url` to the new tag and `sha256` to:
#   curl -L https://github.com/MIKALAKE/raboj/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
class Raboj < Formula
  desc "AI usage in the macOS menu bar: every provider, every account"
  homepage "https://github.com/MIKALAKE/raboj"
  url "https://github.com/MIKALAKE/raboj/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "a09c89333de2f338284f2ffb110037b01ee9b34e97898b848ea3d18e0ea83d06"
  license "MIT"
  head "https://github.com/MIKALAKE/raboj.git", branch: "main"

  depends_on macos: :sonoma

  def install
    version_string = build.head? ? "0.0.0-head" : version.to_s
    system "/usr/libexec/PlistBuddy", "-c", "Set :CFBundleShortVersionString #{version_string}", "Resources/Info.plist"
    # Homebrew already sandboxes the build; SwiftPM's own manifest sandbox can't nest inside it.
    system "make", "app", "EXTRA_SWIFT_FLAGS=--disable-sandbox"
    prefix.install "build/Raboj.app"
  end

  def caveats
    <<~EOS
      Răboj was installed to:
        #{opt_prefix}/Raboj.app

      Put it in your Applications folder and open it:
        ln -sf #{opt_prefix}/Raboj.app ~/Applications/Raboj.app
        open ~/Applications/Raboj.app
    EOS
  end

  test do
    assert_path_exists prefix/"Raboj.app/Contents/MacOS/Raboj"
  end
end
