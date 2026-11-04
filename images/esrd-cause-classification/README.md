# ESRD cause classification diagram

`draw.py` generates `../esrd-cause-classification-placeholder.svg`. The existing
PNG at the same location is embedded in `quarto/statistical_methods.qmd`.
This is the first example of the repository's Python figure-source convention.

## Regenerate

From the repository root:

```sh
python3 images/esrd-cause-classification/draw.py
inkscape images/esrd-cause-classification-placeholder.svg --export-filename=images/esrd-cause-classification-placeholder.png
```

SVG generation uses Python 3 standard libraries only, with no network access.
Paths resolve relative to the script, so it can also be invoked from another
working directory. PNG export requires Inkscape and the DejaVu Sans font.
Validated with Inkscape 1.4; other renderer/font versions may change pixels.
Commit source, assets, and regenerated outputs together after visual inspection.
The website consumes the committed PNG; its build does not run Python or Inkscape.

## Provenance and scope

The script was reconstructed from the compact diagram in the design conversation.
Its PNG render was verified pixel-for-pixel against the existing repository PNG
when the source was added. The original PNG is retained unchanged.
This is a public-methods illustration, not an analysis output: it reads no patient
data and makes no model calls. Example categories correspond to the public
`references/esrd-cause-categories.csv` mapping.

The diagram remains a placeholder. It summarizes replies in one dataset and uses
shared cloud routing lines. Showing five separate returned datasets, highlighting
a real classification disagreement, and revising arrow routing remain future
visual revisions; this source-preservation change does not implement them.

## Logo assets

Assets are stored locally and embedded as data URIs in the generated SVG. No logo
is downloaded during regeneration. Brand marks belong to their respective owners;
use here identifies software and services and does not imply endorsement.

| Asset | Source used in the design conversation |
| --- | --- |
| `r.svg` | [Simple Icons R icon](https://github.com/simple-icons/simple-icons/blob/develop/icons/r.svg) (monochrome brand icon) |
| `ellmer.png` | [ellmer package sticker](https://github.com/tidyverse/ellmer/blob/main/man/figures/logo.png) |
| `openai.svg` | [Lobe Icons: openai.svg](https://github.com/lobehub/lobe-icons/blob/master/packages/static-svg/icons/openai.svg) |
| `claude.svg` | [Lobe Icons: claude-color.svg](https://github.com/lobehub/lobe-icons/blob/master/packages/static-svg/icons/claude-color.svg) |
| `gemini.svg` | [Lobe Icons: gemini-color.svg](https://github.com/lobehub/lobe-icons/blob/master/packages/static-svg/icons/gemini-color.svg) |
| `ollama.svg` | [Lobe Icons: ollama.svg](https://github.com/lobehub/lobe-icons/blob/master/packages/static-svg/icons/ollama.svg) |
| `qwen.svg` | [Lobe Icons: qwen-color.svg](https://github.com/lobehub/lobe-icons/blob/master/packages/static-svg/icons/qwen-color.svg) |
| `meta.svg` | [Lobe Icons: meta-color.svg](https://github.com/lobehub/lobe-icons/blob/master/packages/static-svg/icons/meta-color.svg) (identifies Llama) |

The source URLs were not pinned in the original conversation. The committed asset
bytes are the reproducible inputs. SVG dimensions were normalized to 64 and
`currentColor` replaced with `#18334e` where present for standalone rendering.
