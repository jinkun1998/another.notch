cask "another-notch" do
  version "1.5.1"
  sha256 "34a230f99f2347b40616f135fd28d8a7e1a6713ddd1c0b701ddaa1513a42cf45"

  url "https://github.com/jinkun1998/another.notch/releases/download/v#{version}/anotherNotch.dmg"
  name "anotherNotch"
  desc "Another Notch app for macOS"
  homepage "https://github.com/jinkun1998/another.notch"

  auto_updates true
  depends_on macos: :sonoma

  app "anotherNotch.app"
end
