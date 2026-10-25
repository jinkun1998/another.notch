cask "another-notch" do
  version "1.4.1"
  sha256 "a13eea46790236d31a3f445a3ba01180a7905f1a70f4f4740844798822327590"

  url "https://github.com/jinkun1998/another.notch/releases/download/v#{version}/anotherNotch.dmg"
  name "anotherNotch"
  desc "Another Notch app for macOS"
  homepage "https://github.com/jinkun1998/another.notch"

  auto_updates true
  depends_on macos: :sonoma

  app "anotherNotch.app"
end
