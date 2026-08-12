---
name: compress-images
description: Compress, shrink, or convert image files locally using Beachman Darkroom — no upload, works offline. Use when asked to "compress this image", "shrink these photos", "optimize images for the website", "make this file smaller", "convert to webp/jpg/png/heic", "batch resize the product shots", or any variant of reducing image file size or changing image format. Also use before attaching large images to email or uploading to Shopify.
---

# Compress Images (Beachman Darkroom)

Local, offline image optimizer and converter. **Never uploads anything** — safe for
unreleased product imagery (Aviator, BE4), press kits, and customer photos.

## Check it's installed

```bash
darkroom --version
```

If that works, skip to Usage.

### If it's missing, offer to build it

Building from source is the smoothest path — a locally-built app carries no macOS
quarantine flag, so there is **no Gatekeeper prompt and no "unidentified developer"
warning**. Ask the user first, then:

```bash
brew install pngquant oxipng webp gifsicle mozjpeg
git clone https://github.com/TheBeachman/beachman-darkroom.git
cd beachman-darkroom && ./packaging/build.sh
./dist/Install.command   # or: cp -R "dist/Beachman Darkroom.app" /Applications/
```

Takes about a minute. Needs Xcode Command Line Tools (`xcode-select --install`) and
Homebrew. If the user doesn't want Homebrew, point them at the prebuilt installer in the
[latest release](https://github.com/TheBeachman/beachman-darkroom/releases/latest)
instead — that one does show a first-launch security prompt, which `Install.command`
clears automatically.

**Never fall back to a web compressor** (TinyPNG, Squoosh, iLoveIMG). Uploading the
user's images is the exact thing this tool exists to prevent. If it can't be installed,
say so and stop.

## Usage

**Shrink images** (safe default — originals untouched, results go to
`~/Documents/Beachman Darkroom/Optimizer/`):
```bash
darkroom optimize --quality 80 ~/Desktop/photos
```

**Replace originals in place** (only when the user asked for exactly that):
```bash
darkroom optimize --in-place --quality 80 ~/Desktop/photos
```

**Convert format** (results go to `~/Documents/Beachman Darkroom/Converter/`;
add `--beside` to save next to the original instead):
```bash
darkroom convert --format webp --quality 80 ~/Desktop/product-shots
darkroom convert --format jpg --bg "#FFFFFF" logo.png
```

**Machine-readable output** — always use `--json` when you need to report numbers back:
```bash
darkroom optimize --quality 80 --json ~/Desktop/photos
```

Folders are walked recursively. Multiple files/folders can be passed at once.

## Options

| Option | Meaning |
|---|---|
| `--quality 1-100` | Target quality, default 80. 80 is the safe default for web. |
| `--lossless` | Optimize only, never re-encode pixels. Use for artwork/logos where any loss is unacceptable. |
| `--in-place` | optimize: replace the original file. Destructive — needs user intent. |
| `--suffix` | optimize: write `name-min.ext` beside the original. |
| `--beside` | convert: write next to the original instead of the library folder. |
| `--format <fmt>` | convert only: png, jpg, jpeg, tiff, heic, heif, webp, bmp, pdf |
| `--bg "#RRGGBB"` | Background when flattening transparency into jpg/bmp/pdf. Default white. |
| `--json` | JSON output for parsing. |

Exit codes: `0` all succeeded · `1` one or more failed · `64` usage error.
**Always check the exit code** — a non-zero exit means at least one file failed, and the
per-file reason is on stderr (or in the JSON `results[].error`).

## Choosing settings

- **Web / Shopify product images**: `optimize --quality 80`, or `convert --format webp --quality 80`
  for maximum savings on modern browsers.
- **Email attachments**: `optimize --quality 75`.
- **Press / print**: `optimize --lossless` — strips metadata and re-packs without touching pixels.
- **Logos and line art (PNG)**: `--lossless`. Quantization can band flat colour.
- **Photos from a phone (HEIC)**: `convert --format jpg` for compatibility, then optimize.

## Rules

- **The default never overwrites anything** — results land in
  `~/Documents/Beachman Darkroom/Optimizer` (or `/Converter`), with `name 2.ext`
  de-duplication. Tell the user where their files ended up.
- **Only use `--in-place` when the user explicitly wants originals replaced**
  ("replace them", "shrink them where they are"). It is destructive and strips EXIF.
- Report actual before/after numbers from the output. Don't estimate savings.
- The tool never makes a file larger — if there's no gain it reports "Already optimal"
  (in the default mode the unchanged file is still copied to the output folder, so
  batches always produce a complete set). That's a success, not a failure.
- Optimizing an already-optimized file gains almost nothing. Don't run it twice.
- Metadata (EXIF, GPS) is stripped as a side effect of optimize. If the user needs EXIF
  preserved, say so before running — there is currently no keep-metadata flag.
- Supported input: PNG, JPG, HEIC/HEIF, WebP, GIF, TIFF, BMP, PSD, AI, ICO, AVIF, and camera
  RAW (DNG/NEF/CR2/CR3/ARW/RW2/RAF/…). RAW and PSD/AI must go through `convert`, not `optimize`.
