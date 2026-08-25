import os

# dmgbuild settings file. This is read by the `dmgbuild` CLI (or Python API).
# It uses environment variables exported by the shell wrapper script:
#  - DMG_APP_PATH: path to the .app bundle to put in the DMG
#  - DMG_VOLUME_NAME: volume name to display when the DMG is mounted
#  - DMG_BACKGROUND: absolute path to the background image to use

APP_PATH = os.environ.get('DMG_APP_PATH')
VOLUME_NAME = os.environ.get('DMG_VOLUME_NAME', 'anotherNotch')
BACKGROUND = os.environ.get('DMG_BACKGROUND', '')
VOLUME_ICON = os.environ.get('DMG_VOLUME_ICON', '')

# If DMG_BACKGROUND not provided, default to the hiDPI TIFF in .background.
if not BACKGROUND:
    base = os.path.join(os.path.dirname(__file__), '.background', 'background.tiff')

# Basic DMG metadata
volume_name = VOLUME_NAME
format = 'UDZO'
compression_level = 9

# Files and symlinks to include in the DMG
files = [APP_PATH] if APP_PATH else []
symlinks = {'Applications': '/Applications'}

# Background image path (dmgbuild will copy this file into the DMG's .background)
background = BACKGROUND


# Window rectangle: ((left, top), (right, bottom))
window_rect = ((0, 0), (660, 400))

# Icon size (points)
icon_size = 128

# Icon locations: map filename (or bundle name) -> (x, y) in window coords
app_basename = os.path.basename(APP_PATH) if APP_PATH else 'anotherNotch.app'
icon_locations = {
    app_basename: (150, 180),
    'Applications': (510, 180),
}

# Misc Finder options
show_statusbar = False
show_tabview = False
show_toolbar = False

# Use the app icon directly instead of a generic disk with a badge.
if VOLUME_ICON and os.path.exists(VOLUME_ICON):
    icon = VOLUME_ICON
