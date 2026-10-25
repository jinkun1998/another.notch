cask "another-notch" do
  version "1.3.2"
  sha256 "35f98046bc9d5bbdda99b9ce52056e8f715f97156288fb8abf9f2825f3950ca4"

  url "https://github.com/jinkun1998/another.notch/releases/download/v#{version}/anotherNotch.dmg"
  name "anotherNotch"
  desc "Another Notch app for macOS"
  homepage "https://github.com/jinkun1998/another.notch"

  auto_updates true
  depends_on macos: :sonoma

  app "anotherNotch.app"
end
