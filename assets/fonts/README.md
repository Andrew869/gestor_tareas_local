# Local Roboto fonts

Roboto-Regular.ttf and Roboto-Medium.ttf are unmodified copies distributed with
Flutter 3.47.1, from `engine/src/flutter/txt/third_party/fonts/` in the Flutter SDK.
Roboto is Copyright Google and licensed under Apache 2.0; see Roboto-LICENSE.txt.
Upstream: https://github.com/googlefonts/roboto-2

The fonts are bundled to avoid a runtime dependency on Google Fonts. The default
web fallback URL also points to this application's origin, never an external CDN.
Scripts outside the bundled fonts' glyph coverage may display missing glyphs;
their task titles are still stored as Unicode text in SQLite.
