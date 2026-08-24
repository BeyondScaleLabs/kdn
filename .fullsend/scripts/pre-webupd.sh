#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="/tmp/workspace"
mkdir -p "$WORKSPACE"

KDN_REPO="${GITHUB_WORKSPACE:-.}"

echo "Extracting Kaiden feature info from ${KDN_REPO}..."

# Extract extension info from each extension's package.json
extensions_json="[]"
for ext_dir in "${KDN_REPO}"/extensions/*/; do
  if [[ -f "${ext_dir}/package.json" ]]; then
    ext_info=$(jq -c '{
      name: .name,
      displayName: (.displayName // .name),
      description: (.description // ""),
      keywords: (.keywords // []),
      contributes: (.contributes | keys // [])
    }' "${ext_dir}/package.json" 2>/dev/null || echo '{}')
    extensions_json=$(echo "$extensions_json" | jq --argjson ext "$ext_info" '. + [$ext]')
  fi
done

# Extract key sections from CLAUDE.md / AGENTS.md
project_overview=""
if [[ -f "${KDN_REPO}/CLAUDE.md" ]]; then
  project_overview=$(cat "${KDN_REPO}/CLAUDE.md")
elif [[ -f "${KDN_REPO}/AGENTS.md" ]]; then
  project_overview=$(cat "${KDN_REPO}/AGENTS.md")
fi

# Get recent significant changes (last 30 days)
recent_changes=""
if git -C "${KDN_REPO}" rev-parse --is-inside-work-tree &>/dev/null; then
  recent_changes=$(git -C "${KDN_REPO}" log --since="30 days ago" \
    --pretty=format:"%h %s" --no-merges 2>/dev/null | head -50 || true)
fi

# Get extension API surface
extension_api_exports=""
if [[ -f "${KDN_REPO}/packages/extension-api/src/extension-api.d.ts" ]]; then
  extension_api_exports=$(grep -E '^export|^  export' \
    "${KDN_REPO}/packages/extension-api/src/extension-api.d.ts" 2>/dev/null \
    | head -100 || true)
fi

# Build the output JSON
jq -n \
  --argjson extensions "$extensions_json" \
  --arg project_overview "$project_overview" \
  --arg recent_changes "$recent_changes" \
  --arg extension_api "$extension_api_exports" \
  '{
    extensions: $extensions,
    project_overview: $project_overview,
    recent_changes: $recent_changes,
    extension_api_surface: $extension_api
  }' > "${WORKSPACE}/kdn-info.json"


cat "${WORKSPACE}/kdn-info.json"

echo "Wrote kdn-info.json ($(wc -c < "${WORKSPACE}/kdn-info.json") bytes)"
echo "Pre-script complete."
