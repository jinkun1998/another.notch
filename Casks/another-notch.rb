  cask "another-notch" do
    version "1.1.0"
    sha256 "deb90cea4a37e970da0f90af3d5cae63581114475625d87244c65c507e66a67c"

    url
    "https://github.com/jinkun1998/another.notch/releases/download/v#{version}/anotherNotch.dmg"
    name "anotherNotch"
    desc "Another Notch app for macOS"
    homepage "https://github.com/jinkun1998/another.notch"

    auto_updates true
    depends_on macos: ">= :sonoma"

    app "anotherNotch.app"
  end
