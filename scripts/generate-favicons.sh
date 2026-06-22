#!/usr/bin/env bash
# =============================================================================
# generate-favicons.sh
# Called by action.yml. All configuration comes from environment variables.
#
# Can also be run locally:
#   FAVICON_IMAGE_PATH=logo.svg FAVICON_PRESET=all FAVICON_OUTPUT_DIR=favicons bash scripts/generate-favicons.sh
#
# Env vars:
#   FAVICON_IMAGE_PATH  (required) path to source image
#   FAVICON_OUTPUT_DIR  where to write output               [default: public/favicons]
#   FAVICON_PRESET      ico-only|minimal|extended|all|custom [default: all]
#   FAVICON_CUSTOM_SIZES comma list, only when FAVICON_PRESET=custom
#   FAVICON_BG_COLOR    hex background for opaque tiles     [default: #ffffff]
#   FAVICON_FORCE       true|false — skip if ICO exists     [default: false]
#   GITHUB_OUTPUT   set automatically by GitHub Actions runner
# =============================================================================
set -euo pipefail

# ── Colour helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}▶  $*${RESET}"; }
success() { echo -e "${GREEN}✔  $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠  $*${RESET}"; }
error()   { echo -e "${RED}✖  $*${RESET}" >&2; exit 1; }
sep()     { echo -e "${BOLD}$(printf '─%.0s' {1..60})${RESET}"; }

# ── Helper: write a GitHub Actions output ─────────────────────────────────────
set_output() {
  local key="$1" val="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${val}" >> "$GITHUB_OUTPUT"
  fi
}

# ── Read configuration from env ───────────────────────────────────────────────
IMAGE_PATH="${FAVICON_IMAGE_PATH:-}"
OUTPUT_DIR="${FAVICON_OUTPUT_DIR:-public/favicons}"
PRESET="${FAVICON_PRESET:-all}"
CUSTOM_SIZES="${FAVICON_CUSTOM_SIZES:-}"
BG_COLOR="${FAVICON_BG_COLOR:-#ffffff}"
FORCE="${FAVICON_FORCE:-false}"

# ── Preset → size mappings ─────────────────────────────────────────────────────
declare -A PRESET_SIZES
PRESET_SIZES["ico-only"]="16 32"
PRESET_SIZES["minimal"]="16 32 144 152"
PRESET_SIZES["extended"]="16 32 57 72 76 114 120 144 152 192"
PRESET_SIZES["all"]="16 24 32 48 57 60 64 70 72 76 96 114 120 128 144 150 152 167 180 192 196 256 310"
PRESET_SIZES["custom"]=""

# ── Validate inputs ────────────────────────────────────────────────────────────
[[ -z "$IMAGE_PATH" ]]   && error "FAVICON_IMAGE_PATH is not set."
[[ ! -f "$IMAGE_PATH" ]] && error "Source image not found: '$IMAGE_PATH'"

if [[ "$PRESET" == "custom" ]]; then
  [[ -z "$CUSTOM_SIZES" ]] && error "FAVICON_PRESET=custom requires FAVICON_CUSTOM_SIZES (e.g. '16,32,180')."
  PRESET_SIZES["custom"]=$(echo "$CUSTOM_SIZES" | tr ',' ' ' | tr -s ' ')
fi

SELECTED_SIZES="${PRESET_SIZES[$PRESET]:-}"
[[ -z "$SELECTED_SIZES" ]] && error "Unknown preset '$PRESET'. Use: ico-only minimal extended all custom"

# ── Skip check ────────────────────────────────────────────────────────────────
ICO_PATH="${OUTPUT_DIR}/favicon.ico"
FORCE_LOWER="${FORCE,,}"

if [[ -f "$ICO_PATH" && "$FORCE_LOWER" != "true" ]]; then
  sep
  warn "Favicons already exist in '${OUTPUT_DIR}/' (favicon.ico found)."
  warn "Set force: 'true' in your workflow step to regenerate."
  sep
  set_output "skipped"         "true"
  set_output "output_path"     "$(realpath "$OUTPUT_DIR")"
  set_output "files_generated" "0"
  set_output "favicon_ico"     ""
  exit 0
fi

# ── Detect source format & best SVG renderer ──────────────────────────────────
EXT_LOWER="${IMAGE_PATH##*.}"
EXT_LOWER="${EXT_LOWER,,}"
IS_SVG=false
[[ "$EXT_LOWER" == "svg" || "$EXT_LOWER" == "svgz" ]] && IS_SVG=true

SVG_RENDERER="imagemagick"
if $IS_SVG; then
  if   command -v inkscape      &>/dev/null; then SVG_RENDERER="inkscape"
  elif command -v rsvg-convert  &>/dev/null; then SVG_RENDERER="rsvg"
  fi
fi

# ── Prepare output directory & log ────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"
LOG_FILE="${OUTPUT_DIR}/generation.log"
: > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

sep
echo -e "${BOLD}  🖼️   Favicon Generator${RESET}"
sep
info "Source image : $IMAGE_PATH"
info "Format       : ${EXT_LOWER}  (SVG=$IS_SVG, renderer=$SVG_RENDERER)"
info "Preset       : $PRESET"
info "Sizes (px)   : $SELECTED_SIZES"
info "Background   : $BG_COLOR"
info "Output dir   : $OUTPUT_DIR"
info "Force regen  : $FORCE_LOWER"
sep

# ═══════════════════════════════════════════════════════════════════════════════
# Rendering helpers
# ═══════════════════════════════════════════════════════════════════════════════

render_square_png() {
  local size="$1"
  local out="${OUTPUT_DIR}/favicon-${size}x${size}.png"

  if $IS_SVG; then
    case "$SVG_RENDERER" in
      inkscape)
        inkscape \
          --export-type=png \
          --export-filename="$out" \
          --export-width="$size" \
          --export-height="$size" \
          --export-background-opacity=0 \
          "$IMAGE_PATH" 2>/dev/null
        ;;
      rsvg)
        rsvg-convert \
          --width="$size" --height="$size" \
          --keep-aspect-ratio \
          --output="$out" \
          "$IMAGE_PATH"
        ;;
      *)
        convert -background none "$IMAGE_PATH" \
          -resize "${size}x${size}" \
          -gravity center -extent "${size}x${size}" \
          "$out"
        ;;
    esac
  else
    convert "$IMAGE_PATH" \
      -filter Lanczos \
      -resize "${size}x${size}" \
      -gravity center \
      -background none -extent "${size}x${size}" \
      "$out"
  fi

  printf '  PNG %4sx%-4s  →  %s\n' "$size" "$size" "$(basename "$out")"
}

render_metro_wide() {
  local w=310 h=150
  local out="${OUTPUT_DIR}/mstile-${w}x${h}.png"

  if $IS_SVG; then
    case "$SVG_RENDERER" in
      inkscape)
        inkscape \
          --export-type=png \
          --export-filename="$out" \
          --export-width="$w" --export-height="$h" \
          "$IMAGE_PATH" 2>/dev/null
        ;;
      rsvg)
        rsvg-convert \
          --width="$w" --height="$h" \
          --keep-aspect-ratio \
          --output="$out" \
          "$IMAGE_PATH"
        ;;
      *)
        convert -background none "$IMAGE_PATH" \
          -resize "${w}x${h}" -gravity center -extent "${w}x${h}" "$out"
        ;;
    esac
  else
    convert "$IMAGE_PATH" \
      -filter Lanczos -resize "${w}x${h}" \
      -gravity center -background none -extent "${w}x${h}" "$out"
  fi

  echo "  PNG ${w}×${h} (Metro wide)  →  $(basename "$out")"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 1 — Render all square PNGs
# ═══════════════════════════════════════════════════════════════════════════════
info "Rendering PNG files…"
GENERATED_PNGS=()

for SIZE in $SELECTED_SIZES; do
  render_square_png "$SIZE"
  GENERATED_PNGS+=("${OUTPUT_DIR}/favicon-${SIZE}x${SIZE}.png")
done

WIDE_METRO=false
if [[ "$PRESET" == "all" ]]; then
  render_metro_wide
  WIDE_METRO=true
fi

success "PNG rendering complete."

# ═══════════════════════════════════════════════════════════════════════════════
# Step 2 — Lossless PNG optimisation
# ═══════════════════════════════════════════════════════════════════════════════
if command -v optipng &>/dev/null; then
  info "Optimising PNGs with optipng…"
  for f in "${GENERATED_PNGS[@]}"; do
    optipng -quiet -o2 "$f" 2>/dev/null || true
  done
  success "Optimisation complete."
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Step 3 — Build favicon.ico (multi-layer)
# ═══════════════════════════════════════════════════════════════════════════════
info "Building favicon.ico…"

ICO_ALLOWED=(16 24 32 48 64 128 256)
ICO_INPUTS=()
for S in "${ICO_ALLOWED[@]}"; do
  PNG="${OUTPUT_DIR}/favicon-${S}x${S}.png"
  if [[ " $SELECTED_SIZES " =~ " $S " && -f "$PNG" ]]; then
    ICO_INPUTS+=("$PNG")
  fi
done

if [[ ${#ICO_INPUTS[@]} -eq 0 ]]; then
  warn "No standard ICO sizes (16/24/32/48/64) found — using smallest available."
  # shellcheck disable=SC2207
  ICO_INPUTS=($(printf '%s\n' "${GENERATED_PNGS[@]}" | head -2))
fi

convert "${ICO_INPUTS[@]}" "$ICO_PATH"
echo "  ICO  →  favicon.ico  (layers: ${ICO_INPUTS[*]##*/})"
success "favicon.ico created."

# ═══════════════════════════════════════════════════════════════════════════════
# Step 4 — Opaque Metro tile variants
# ═══════════════════════════════════════════════════════════════════════════════
info "Creating opaque tile variants for Windows Metro / IE…"
MSTILE_GENERATED=false
for SIZE in 70 144 150 310; do
  SRC="${OUTPUT_DIR}/favicon-${SIZE}x${SIZE}.png"
  if [[ -f "$SRC" ]]; then
    DEST="${OUTPUT_DIR}/mstile-${SIZE}x${SIZE}.png"
    convert "$SRC" -background "$BG_COLOR" -flatten "$DEST"
    echo "  mstile ${SIZE}×${SIZE}  →  $(basename "$DEST")"
    MSTILE_GENERATED=true
  fi
done

if $WIDE_METRO && [[ -f "${OUTPUT_DIR}/mstile-310x150.png" ]]; then
  convert "${OUTPUT_DIR}/mstile-310x150.png" \
    -background "$BG_COLOR" -flatten \
    "${OUTPUT_DIR}/mstile-310x150.png"
fi

$MSTILE_GENERATED && success "Opaque tile variants created."

# ═══════════════════════════════════════════════════════════════════════════════
# Step 5 — browserconfig.xml
# ═══════════════════════════════════════════════════════════════════════════════
NEED_BROWSERCONFIG=false
for S in 70 144 150 310; do
  [[ " $SELECTED_SIZES " =~ " $S " ]] && NEED_BROWSERCONFIG=true && break
done
[[ "$PRESET" == "all" ]] && NEED_BROWSERCONFIG=true

if $NEED_BROWSERCONFIG; then
  info "Writing browserconfig.xml…"
  {
    echo '<?xml version="1.0" encoding="utf-8"?>'
    echo '<browserconfig>'
    echo '  <msapplication>'
    echo '    <tile>'
    [[ -f "${OUTPUT_DIR}/mstile-70x70.png"   ]] && \
      echo '      <square70x70logo   src="/mstile-70x70.png"/>'
    [[ -f "${OUTPUT_DIR}/mstile-150x150.png" ]] && \
      echo '      <square150x150logo src="/mstile-150x150.png"/>'
    [[ -f "${OUTPUT_DIR}/mstile-310x310.png" ]] && \
      echo '      <square310x310logo src="/mstile-310x310.png"/>'
    $WIDE_METRO && \
      echo '      <wide310x150logo   src="/mstile-310x150.png"/>'
    echo "      <TileColor>${BG_COLOR}</TileColor>"
    echo '    </tile>'
    echo '  </msapplication>'
    echo '</browserconfig>'
  } > "${OUTPUT_DIR}/browserconfig.xml"
  success "browserconfig.xml written."
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Step 6 — site.webmanifest
# ═══════════════════════════════════════════════════════════════════════════════
MANIFEST_SIZES=(192 196 256)
MANIFEST_ENTRIES=()
for S in "${MANIFEST_SIZES[@]}"; do
  PNG="${OUTPUT_DIR}/favicon-${S}x${S}.png"
  if [[ " $SELECTED_SIZES " =~ " $S " && -f "$PNG" ]]; then
    MANIFEST_ENTRIES+=("    {\"src\": \"/favicon-${S}x${S}.png\", \"sizes\": \"${S}x${S}\", \"type\": \"image/png\"}")
  fi
done

if [[ ${#MANIFEST_ENTRIES[@]} -gt 0 ]]; then
  info "Writing site.webmanifest…"
  ICONS_JSON=""
  for i in "${!MANIFEST_ENTRIES[@]}"; do
    ICONS_JSON+="${MANIFEST_ENTRIES[$i]}"
    [[ $i -lt $(( ${#MANIFEST_ENTRIES[@]} - 1 )) ]] && ICONS_JSON+=","
    ICONS_JSON+=$'\n'
  done
  cat > "${OUTPUT_DIR}/site.webmanifest" << MANIFEST
{
  "name": "",
  "short_name": "",
  "icons": [
${ICONS_JSON}  ],
  "theme_color": "${BG_COLOR}",
  "background_color": "${BG_COLOR}",
  "display": "standalone"
}
MANIFEST
  success "site.webmanifest written."
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Step 7 — HTML <head> snippet (always generated, always relative paths)
# ═══════════════════════════════════════════════════════════════════════════════
info "Writing favicon-snippet.html…"
HTML="${OUTPUT_DIR}/favicon-snippet.html"
{
  echo "<!-- ================================================================"
  echo "     Favicon HTML Snippet — generated by andreia/generate-favicons"
  echo "     Copy the tags below into your site's <head>."
  echo "     ================================================================ -->"
  echo ""

  echo "<!-- Universal fallback -->"
  echo '<link rel="shortcut icon" href="/favicon.ico">'
  echo ""

  echo "<!-- Standard PNG icons -->"
  for S in 16 32 48 64 96 128 192 196 256; do
    if [[ " $SELECTED_SIZES " =~ " $S " && -f "${OUTPUT_DIR}/favicon-${S}x${S}.png" ]]; then
      echo "<link rel=\"icon\" type=\"image/png\" sizes=\"${S}x${S}\" href=\"/favicon-${S}x${S}.png\">"
    fi
  done
  echo ""

  echo "<!-- Apple touch icons -->"
  for S in 57 60 72 76 114 120 144 152 167 180; do
    if [[ " $SELECTED_SIZES " =~ " $S " && -f "${OUTPUT_DIR}/favicon-${S}x${S}.png" ]]; then
      echo "<link rel=\"apple-touch-icon\" sizes=\"${S}x${S}\" href=\"/favicon-${S}x${S}.png\">"
    fi
  done
  echo ""

  if [[ -f "${OUTPUT_DIR}/mstile-144x144.png" ]]; then
    echo "<!-- Windows Metro / IE tile -->"
    echo "<meta name=\"msapplication-TileImage\" content=\"/mstile-144x144.png\">"
    echo "<meta name=\"msapplication-TileColor\" content=\"${BG_COLOR}\">"
  fi
  if [[ -f "${OUTPUT_DIR}/browserconfig.xml" ]]; then
    echo "<meta name=\"msapplication-config\" content=\"/browserconfig.xml\">"
  fi
  echo ""

  if [[ -f "${OUTPUT_DIR}/site.webmanifest" ]]; then
    echo "<!-- PWA / Android Chrome -->"
    echo '<link rel="manifest" href="/site.webmanifest">'
  fi
  echo ""

  echo "<!-- Theme color -->"
  echo "<meta name=\"theme-color\" content=\"${BG_COLOR}\">"
} > "$HTML"
success "favicon-snippet.html written."

# ═══════════════════════════════════════════════════════════════════════════════
# Step 8 — Summary & GitHub Actions outputs
# ═══════════════════════════════════════════════════════════════════════════════
sep
echo -e "${BOLD}  📦  Output Summary${RESET}"
sep

FILE_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 -type f ! -name "*.log" | wc -l)
TOTAL_SIZE=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)

echo ""
printf "  %-20s %s\n" "Files generated:"  "$FILE_COUNT"
printf "  %-20s %s\n" "Total size:"       "$TOTAL_SIZE"
printf "  %-20s %s\n" "Output directory:" "$(realpath "$OUTPUT_DIR")"
echo ""
find "$OUTPUT_DIR" -maxdepth 1 -type f ! -name "*.log" \
  -printf "  %-40f  %6k KB\n" | sort
echo ""
sep
echo -e "${GREEN}${BOLD}  ✅  Done! All favicons written to: ${OUTPUT_DIR}/${RESET}"
sep

set_output "skipped"         "false"
set_output "output_path"     "$(realpath "$OUTPUT_DIR")"
set_output "files_generated" "$FILE_COUNT"
set_output "favicon_ico"     "$(realpath "$ICO_PATH")"
