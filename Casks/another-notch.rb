cask "another-notch" do
  version "1.3.1"
  sha256 "19d139478e53525a9708e234641eff761ee292c318d29ae9b5c4af67559ff7c6"

  url "https://github.com/jinkun1998/another.notch/releases/download/v#{version}/anotherNotch.dmg"
  name "anotherNotch"
  desc "Another Notch app for macOS"
  homepage "https://github.com/jinkun1998/another.notch"

  auto_updates true
  depends_on macos: :sonoma

  app "anotherNotch.app"
end
