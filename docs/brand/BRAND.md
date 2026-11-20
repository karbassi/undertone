# Sorl brand

Sorl is a macOS menu bar app. Paste a YouTube link, or a link to any site yt-dlp supports, and it plays only the audio in the background.

## Name

- Always lowercase in the wordmark: **sorl**. In running text, write "Sorl" at the start of a sentence and in titles, the same way you would any proper noun.
- How to say it: one syllable, like "soar" with an L on the end. IPA /soːɭ/. It's Swedish for the murmur or buzz of voices, or a faint purling sound.

## Files

| File | What it is |
| --- | --- |
| `sorl-icon.svg` | App icon, 1024 × 1024 canvas, body 824 × 824 inset 100, corner radius 185. Layers are grouped as `background`, `foreground` and `glass` so they can be brought into Icon Composer. |
| `sorl-icon-1024.png` | The same icon rendered at 1024 px. |
| `sorl-icon-params.json` | The playground settings that generate the icon. Paste them back into the playground to tweak it. |
| `sorl-glyph-idle.svg` | Menu bar glyph: nothing loaded. A flat thread with a soft bump. |
| `sorl-glyph-loading.svg` | Menu bar glyph: resolving a link. The wave drawn as dots. |
| `sorl-glyph-playing.svg` | Menu bar glyph: playing. One full wave. |
| `sorl-glyph-paused.svg` | Menu bar glyph: paused. The wave breaks at its midpoint. |

## App icon

- **Concept:** two threads, one of sound and one of its echo, running off both edges of the tile. The murmur was going before you looked and keeps going after.
- **Tile:** Ink gradient, #33383D at the top to #15171A at the bottom. No glass sheen and no rim light are baked in. macOS 26 adds Liquid Glass only when the layers go through Icon Composer into a `.icon` file; a PNG or `.icns` stays flat.
- **Threads:** paper white, #FBF8F2 to #E4DED2. The main voice has a soft drop shadow and a thin highlight along its top edge. The second voice is about half the weight, at 29% opacity, about a fifth of a period behind (1.15 rad).
- **Small sizes:** at 16 px only the main thread is visible. That's intended.
- **Don't:** add a play triangle, waveform bars or a glow. Don't recolor the threads outside the palettes below. Don't put the icon on a busy photo.

## Menu bar glyph

- Template images: black on transparent, 18 × 18 pt viewBox, 1.7 pt round strokes. Set `isTemplate = true` so macOS tints them for light and dark menu bars.
- The four states differ by shape, never only by color or opacity: idle (bump), loading (dots), playing (wave), paused (broken wave).
- These map to the four states in `StatusItemController.updateIcon()`: `isResolving` is loading, `isPlaying` is playing, a loaded track that isn't playing is paused, and no track is idle.

## Wordmark

- Lowercase **sorl** in SF Pro Rounded Semibold, letter-spacing −0.02em.
- Keep it as live system text (`.font(.system(.largeTitle, design: .rounded, weight: .semibold))` in SwiftUI, `ui-rounded` on the web). Don't outline SF glyphs into a logo file; Apple's font license doesn't allow it.
- **Lockup:** icon on the left, wordmark on the right, vertically centered. The gap is about a quarter of the icon's height, and the wordmark's cap height is about 60% of the icon's height.
- On dark surfaces use #F5F5F7, and on light ones #1D1D1F.

## Palette

The brand palette is **Ink**: graphite and paper. It's neutral, so the app sits quietly next to Control Center.

| Token | Light | Dark |
| --- | --- | --- |
| Tile top | #33383D | #33383D |
| Tile bottom | #15171A | #15171A |
| Thread | #FBF8F2 → #E4DED2 | same |
| Panel accent | #3D4349 | #E4DED2 |
| Text on accent (play button) | #FFFFFF | #15171A |
| Current row text | #1D2125 | #F3EFE6 |
| Current row background | #ECEDEF | #3A3E44 |

- Ink replaces the Panel v2 blue (#0a64d8) everywhere the accent is used: play button, scrubber fill, rest marks, star, Clear, speed pill and the current row.
- Contrast: accent 9.3:1 on #f6f6f8 and 12.7:1 on #1c1c1e; current text 13.8:1 on its row in light mode and 9.4:1 in dark mode.
- **Current row rule:** the Ink current-row background is close to the hover row (#f2f2f5), so the current row's title is always **semibold**. That's the cue that tells it apart from a hovered row; don't drop it.
- Panel v2's other tokens (background #f6f6f8, text #1d1d1f / #6e6e73 / #8e8e93, hover #f2f2f5) don't change.

## Type

| Use | Face | Size and weight |
| --- | --- | --- |
| Wordmark, README and site headings | SF Pro Rounded | Semibold |
| Player title | SF Pro (system) | 14 semibold |
| Rows, body | SF Pro (system) | 13 regular, current row semibold |
| Meta and times | SF Pro (system) | 11, tabular numbers |

## Voice

- **Tagline:** Just the sound. Quickly.
- **Alternates:** "The murmur in the background." and "Paste a link. Keep the sound. Close the tab."
- **Short description:** Sorl is a menu bar player for macOS. Paste a YouTube link, or one from any site yt-dlp supports, and it plays only the audio, in the background. Queue what's next, save what you love, and pick up where you left off.
- **How to say it:** One syllable, like "soar" with an L on the end: sorl /soːɭ/. Swedish for the murmur of voices.
- **Credit:** Inspired by and forked from [Undertone](https://github.com/JoaoCVerissimo/undertone) by João Veríssimo (MIT).
- **Tone:** plain and calm. Say what happens ("Added to Up next"), not how the app works. No exclamation marks.

## License

Not applied yet. When the project moves to `karbassi/sorl`, change the top of `LICENSE` to the text below. João's copyright line and the whole permission notice stay word for word; only the first copyright line is new.

```
MIT License

Copyright (c) 2026 Ali Karbassi
Copyright (c) 2026 João Veríssimo

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

## Design sources

- Wave playground (regenerates the icon from `sorl-icon-params.json`): https://claude.ai/artifact/VxfySa9jfNSB4MeR2whxU4
- Brand lab (accent across the app, wordmark knobs): https://claude.ai/artifact/Fq1bvgJge1J3ZGv2WCSQLp
- Wave studies: https://claude.ai/artifact/34n7Vq4ZUC8DZDJ4F4Ktze
- Earlier directions: https://claude.ai/artifact/TLpMPhrucNbaVwTPTFiHEs
