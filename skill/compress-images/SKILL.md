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

If that fails, the app isn't installed on this Mac. Get `Beachman Darkroom - Install.zip`
from the company Google Drive, unzip, double-click `Install.command`. Do not fall back to
a web compressor (TinyPNG, Squoosh, iLoveIMG) — uploading company images is the exact
thing this tool exists to prevent.

## Usage

**Shrink images in place** (replaces originals — the common case):
```bash
darkroom optimize --quality 80 ~/Desktop/photos
```

**Keep originals**, writing `name-min.ext` alongside:
```bash
darkroom optimize --quality 80 --suffix photo.jpg
```

**Convert format:**
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
| `--suffix` | Write `name-min.ext` instead of replacing the original. |
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

- **Optimize replaces originals by default.** If the images are irreplaceable or the user
  hasn't said it's fine, use `--suffix`, or copy them first and say what you did.
- Report actual before/after numbers from the output. Don't estimate savings.
- The tool never makes a file larger — if there's no gain it reports "Already optimal"
  and leaves the file untouched. That's a success, not a failure.
- Optimizing an already-optimized file gains almost nothing. Don't run it twice.
- Metadata (EXIF, GPS) is stripped as a side effect of optimize. If the user needs EXIF
  preserved, say so before running — there is currently no keep-metadata flag.
- Supported input: PNG, JPG, HEIC/HEIF, WebP, GIF, TIFF, BMP, PSD, AI, ICO, AVIF, and camera
  RAW (DNG/NEF/CR2/CR3/ARW/RW2/RAF/…). RAW and PSD/AI must go through `convert`, not `optimize`.
