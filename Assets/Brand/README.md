# Lyssna branding

The black microphone and green disc are shared with the sibling `lyssna-app` project. `LyssnaMark.png` is copied from its `assets/lyssna.png`; `Lyssna.svg` follows the geometry in `frontend/brand.tsx` and uses a full green square so iOS can apply its own icon mask.

The glyph derives from Lucide's MicVocal icon (ISC), as documented in the desktop project's branding source. Lucide copyright and permission notice are reproduced in `LICENSE.lucide`.

`Assets/AppIcon/sources/Lyssna.png` is the 1024-pixel opaque primary icon rendered from the vector. The packaging utility produces the required device sizes. The resource bundle also includes a copy for the settings header.
