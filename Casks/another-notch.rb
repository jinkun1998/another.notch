cask "another-notch" do
  version "1.3.2"
  sha256 "08216b3bf727c4170e024bf4bf720dfa8012bb419ce1145ab8633fb0faa13879"

  url "https://github.com/jinkun1998/another.notch/releases/download/v#{version}/anotherNotch.dmg"
  name "anotherNotch"
  desc "Another Notch app for macOS"
  homepage "https://github.com/jinkun1998/another.notch"

  auto_updates true
  depends_on macos: :sonoma

  app "anotherNotch.app"
end
