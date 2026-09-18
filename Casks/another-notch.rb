cask "another-notch" do
  version "1.2.0"
  sha256 "28168f121d2ba3eb07196b3a4b8825cf53ccf88881fa81b6331fc94fb68625de"

  url "https://github.com/jinkun1998/another.notch/releases/download/v#{version}/anotherNotch.dmg"
  name "anotherNotch"
  desc "Another Notch app for macOS"
  homepage "https://github.com/jinkun1998/another.notch"

  auto_updates true
  depends_on macos: :sonoma

  app "anotherNotch.app"
end
