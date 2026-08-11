<div align="center">

# Beachman Darkroom

**A macOS image optimizer and converter that never touches the network.**

Drag in a folder of photos. Get them back 50–90% smaller. Nothing uploads, nothing
phones home, and it works on a plane.

![Beachman Darkroom](docs/screenshot-optimizer.png)

</div>

---

## Why this exists

We were using an app from the Mac App Store called "ImageOptim" to compress product
photos. It is not the well-known open-source ImageOptim — it's a different app with the
same name (`com.luoxiao.ImageOptim`), and pulling apart its binary turned up this:

```
https://tinypng.com/backend/opt/shrink
com.luoxiao.tinypng.monthly / .year / .forover
```

That endpoint is TinyPNG's private web backend — the one their own website calls, not
their documented API. So every image we compressed was being uploaded to a third party,
by an app that charges a subscription to relay them, and which also ships Microsoft
AppCenter and LeanCloud analytics with `NSAllowsArbitraryLoads` enabled. Its own consent
text confirms the upload.

For a company with unreleased vehicles, that's the wrong pipe to push press photos
through. So we built a replacement.

The punchline: **there was never anything to steal.** TinyPNG's method is public —
palette quantization with dithering for PNG, trellis-quantized re-encoding for JPEG — and
the reference implementations are open source and excellent. Darkroom just runs them
locally, wrapped in an interface people will actually use.

## What it does

**Optimizer** — shrink files in place, or alongside as `name-min.ext`.

| Format | Engine | Typical |
|---|---|---|
| PNG | pngquant (quantization + dithering) → oxipng (deflate re-squeeze) | −60–80% |
| JPEG | mozjpeg (trellis quantization, progressive) | −50–80% |
| WebP | cwebp | −25% |
| GIF | gifsicle `-O3` | varies |
| HEIC / TIFF | ImageIO re-encode | varies |

Never writes a file that came out bigger — if there's no gain, the original is left
alone. Strips EXIF and GPS as a side effect. A lossless mode skips pixel re-encoding
entirely, for logos and line art where quantization can band flat colour.

**Converter** — reads PNG, JPG, HEIC/HEIF, WebP, GIF, TIFF, BMP, PSD, AI, ICO, AVIF and
camera RAW (DNG, NEF, CR2, CR3, ARW, RW2, RAF, CRW, MRW, PEF, X3F). Writes PNG, JPG,
JPEG, TIFF, HEIC, HEIF, WebP, BMP, PDF. Picks a background colour when flattening
transparency into a format without an alpha channel.

Real numbers from the test set:

```
2.4 MB PNG  →  584 KB   (−75%)   pngquant + oxipng
5.9 MB JPG  →  1.2 MB   (−80%)   mozjpeg q80
2.1 MB PNG  →  112 KB   (−95%)   converted to WebP
```

The screenshot at the top of this README was compressed by the app itself: 504 KB → 46 KB.

## Install

Download `Beachman Darkroom - Install.zip` from the latest release, unzip, and
double-click **Install.command**. It copies the app to `/Applications`, clears the
quarantine flag, and installs the `darkroom` CLI on your `PATH`.

Requires **macOS 13+ on Apple Silicon**. The bundled engines are arm64 builds.

<details>
<summary>Building from source</summary>

```bash
brew install pngquant oxipng webp gifsicle mozjpeg
./packaging/build.sh
```

Needs Xcode Command Line Tools. The build copies each engine and its transitive dylib
closure into the bundle, rewrites the load paths to `@rpath`, and ad-hoc signs the
result, so the finished `.app` runs on Macs without Homebrew.

</details>

## Command line

The app is also a CLI. Same engines, no window.

```bash
darkroom optimize --quality 80 ~/Desktop/photos      # folders walked recursively
darkroom optimize --lossless logo.png                # never re-encode pixels
darkroom optimize --suffix photo.jpg                 # keep the original
darkroom convert --format webp --quality 80 shots/
darkroom convert --format jpg --bg "#FFFFFF" logo.png
```

| Option | |
|---|---|
| `--quality 1-100` | Target quality, default 80 |
| `--lossless` | Optimize only, never re-encode pixels |
| `--suffix` | Write `name-min.ext` instead of replacing the original |
| `--format <fmt>` | png, jpg, jpeg, tiff, heic, heif, webp, bmp, pdf |
| `--bg "#RRGGBB"` | Background when flattening alpha into jpg/bmp/pdf |
| `--json` | Machine-readable output |

Exit codes: `0` all succeeded · `1` one or more failed · `64` usage error.

## Using it from Claude Code

`skill/compress-images/` is a [Claude Code](https://claude.com/claude-code) skill. Drop it
into `~/.claude/skills/` and any Claude session on that machine can compress images for
you on request — "make these product shots web-ready", "convert this folder to WebP" —
without asking how.

```bash
cp -R skill/compress-images ~/.claude/skills/
```

The skill teaches Claude the flags, when lossless beats lossy, to check exit codes, and
to warn before replacing originals it can't get back. It also tells Claude not to fall
back to a web compressor if the tool is missing, which is rather the point.

`--json` exists for this: agents get structured before/after bytes, percentages, the
engine used per file, and per-file error reasons, instead of parsing console text.

## How it works

A small SwiftUI front end over battle-tested command-line compressors. Decoding and
non-specialised encoding go through Apple's ImageIO (which is what gives us PSD, ICO,
AVIF and RAW for free); PDF and AI input is rasterised with PDFKit. The specialised
work is handed to the engines below, run as subprocesses.

There's no clever new algorithm here, and that's deliberate — the open-source
implementations of this problem are better than anything worth reinventing. The value
added is that they're wrapped in something a non-technical person can use, they ship as
one signed bundle with no dependency install, and the data never leaves the machine.

## Third-party engines

| | License |
|---|---|
| [pngquant / libimagequant](https://pngquant.org) | GPL v3 |
| [oxipng](https://github.com/oxipng/oxipng) | MIT |
| [mozjpeg](https://github.com/mozilla/mozjpeg) | BSD-3 / IJG / zlib |
| [libwebp](https://chromium.googlesource.com/webm/libwebp) | BSD-3 |
| [gifsicle](https://github.com/kohler/gifsicle) | GPL v2 |

Full notices in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## License

GPL v3 — see [LICENSE](LICENSE). Darkroom distributes pngquant and gifsicle binaries in
its app bundle, so the combined work is licensed to match. Practically: use it, fork it,
change it, ship it — keep it open.

---

<div align="center">
<sub>Built at <a href="https://beachman.ca">Beachman Motor Company</a>, Toronto.</sub>
</div>
