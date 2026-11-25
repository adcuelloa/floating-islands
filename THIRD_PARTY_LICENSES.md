# Third-Party Licenses

Floating Islands is licensed under the MIT License ([LICENSE](LICENSE)). The repository incorporates general-purpose interface icon path data derived from the third-party project listed below.

## Lucide Icons

- **Project:** [Lucide](https://lucide.dev/) (`https://github.com/lucide-icons/lucide`)
- **Pinned Revision:** Tag `1.79.0` (commit `c26ce5515667640ca2753e095ba319d225fc0d8d`)
- **Used In:** `plugin/theme/Icons.js` (21 icons: `layout-grid`, `terminal`, `globe`, `code-xml`, `file-text`, `monitor`, `app-window`, `skip-back`, `skip-forward`, `play`, `pause`, `sliders-horizontal`, `moon`, `coffee`, `bell-off`, `volume-2`, `volume-x`, `sun`, `wifi`, `bluetooth`, `chevron-right`)
- **Modifications:** SVG shape primitives (`<rect>`, `<circle>`, `<line>`) converted to SVG path data for `QtQuick.Shapes` `PathSvg`; leading relative `m` commands normalized to absolute `M` (+ `l`) for safe multi-subpath concatenation; `play` and `pause` rendered filled for transport emphasis; strokes rendered at width `1.8` in `StrokeIcon.qml`.

### ISC License (Lucide Icons)

```text
ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```

### The MIT License (Feather-Derived Lucide Icons)

Among the icons used in `plugin/theme/Icons.js`, `terminal`, `monitor`, `moon`, and `chevron-right` are derived from the Feather project and are subject to the following MIT License notice:

```text
The MIT License (MIT)

Copyright (c) 2013-present Cole Bemis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
