cask "another-notch" do
  version "1.3.0"
  sha256 "c4f994b598a9f1f552a5db94c8d6796ac9a3db274d8eb76c5f613fed735132b9"

  url "https://github.com/jinkun1998/another.notch/releases/download/v#{version}/anotherNotch.dmg"
  name "anotherNotch"
  desc "Another Notch app for macOS"
  homepage "https://github.com/jinkun1998/another.notch"

  auto_updates true
  depends_on macos: :sonoma

  app "anotherNotch.app"
end
