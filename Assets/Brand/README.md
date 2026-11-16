# Lyssna branding

The black microphone and green disc are shared with the sibling `lyssna-app` project. `LyssnaMark.png` is copied from its `assets/lyssna.png`; `Lyssna.svg` follows the geometry in `frontend/brand.tsx` with a green foreground disc on an opaque charcoal tile. Subtle gradients provide a restrained highlight on the disc and microphone; iOS applies its own rounded tile mask.

The glyph derives from Lucide's MicVocal icon (ISC), as documented in the desktop project's branding source. Lucide copyright and permission notice are reproduced in `LICENSE.lucide`.

`Assets/AppIcon/sources/Lyssna.png` is the 1024-pixel opaque primary icon rendered from the vector. The packaging utility produces the required device sizes. The resource bundle also includes a copy for the settings header.

The packaged icon declares `UIPrerenderedIcon` because the artwork already includes gloss. Keeping green on the foreground disc avoids relying on a solid green background for the mark's contrast. System dark/tinted appearances still require device verification; see [Apple's icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons).

The launch artwork in `Assets/LaunchScreen` reuses the green disc and microphone on a uniform dark background matching the launch storyboard. Packaging compiles that storyboard for iPhone and iPad, replaces Spotify's original launch storyboard, and selects a content-specific launch name.
