cask "another-notch" do
  version "1.5.0"
  sha256 "f34e54d0692c39055475114327d6e9552ac10512b485be6c20ceb792e2b584b9"

  url "https://github.com/jinkun1998/another.notch/releases/download/v#{version}/anotherNotch.dmg"
  name "anotherNotch"
  desc "Another Notch app for macOS"
  homepage "https://github.com/jinkun1998/another.notch"

  auto_updates true
  depends_on macos: :sonoma

  app "anotherNotch.app"
end
