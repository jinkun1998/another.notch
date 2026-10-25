cask "another-notch" do
  version "1.4.0"
  sha256 "27375b11c808a6f83b08042897405db7664d147129959f7879d0a6c5c78e73f5"

  url "https://github.com/jinkun1998/another.notch/releases/download/v#{version}/anotherNotch.dmg"
  name "anotherNotch"
  desc "Another Notch app for macOS"
  homepage "https://github.com/jinkun1998/another.notch"

  auto_updates true
  depends_on macos: :sonoma

  app "anotherNotch.app"
end
