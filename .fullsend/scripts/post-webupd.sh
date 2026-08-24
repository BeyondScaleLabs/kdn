#!/usr/bin/env bash
set -euo pipefail

# Prefer the validated iteration directory set by the harness
if [[ -n "${FULLSEND_VALIDATED_ITERATION_DIR:-}" ]]; then
  RESULT_FILE="${FULLSEND_VALIDATED_ITERATION_DIR}/agent-result.json"
  FILES_DIR="${FULLSEND_VALIDATED_ITERATION_DIR}/files"
else
  RESULT_FILE=""
  FILES_DIR=""
  for dir in iteration-*/output; do
    if [[ -f "${dir}/agent-result.json" ]]; then
      RESULT_FILE="${dir}/agent-result.json"
      FILES_DIR="${dir}/files"
    fi
  done
fi

if [[ -z "${RESULT_FILE}" ]] || [[ ! -f "${RESULT_FILE}" ]]; then
  echo "ERROR: agent-result.json not found"
  exit 1
fi

if ! jq empty "${RESULT_FILE}" 2>/dev/null; then
  echo "ERROR: agent-result.json is not valid JSON"
  exit 1
fi

STATUS=$(jq -r '.status // ""' "${RESULT_FILE}")

case "${STATUS}" in
  no_changes)
    echo "No website changes needed. Exiting."
    exit 0
    ;;
  changes_found)
    echo "Agent found changes to apply."
    ;;
  error)
    echo "Agent reported an error."
    jq -r '.pr_body // "No details"' "${RESULT_FILE}"
    exit 1
    ;;
  *)
    echo "ERROR: Unknown or missing status '${STATUS}'"
    exit 1
    ;;
esac

if [[ ! -d "${FILES_DIR}" ]]; then
  echo "ERROR: No files directory found at ${FILES_DIR}"
  exit 1
fi

PR_TITLE=$(jq -r '.pr_title // "docs: automated website update"' "${RESULT_FILE}")
PR_BODY=$(jq -r '.pr_body // "Automated update from webupd agent."' "${RESULT_FILE}")

WEBSITE_REPO="BeyondScaleLabs/website"
BRANCH_NAME="fullsend/website-update-$(date +%Y%m%d-%H%M%S)"

# Use WEBSITE_GH_TOKEN for cross-repo access, fall back to GH_TOKEN
PUSH_TOKEN="${WEBSITE_GH_TOKEN:-${GH_TOKEN}}"

WORK_DIR=$(mktemp -d)
echo "Cloning website repo..."
git clone "https://x-access-token:${PUSH_TOKEN}@github.com/${WEBSITE_REPO}.git" "${WORK_DIR}/website" --depth 1

cd "${WORK_DIR}/website"
git checkout -b "${BRANCH_NAME}"

# Apply changes from agent output
CHANGES_APPLIED=0
while IFS= read -r file; do
  rel_path="${file#${FILES_DIR}/}"
  dest="${WORK_DIR}/website/${rel_path}"
  mkdir -p "$(dirname "${dest}")"
  cp "${file}" "${dest}"
  git add "${rel_path}"
  CHANGES_APPLIED=$((CHANGES_APPLIED + 1))
  echo "Applied: ${rel_path}"
done < <(find "${FILES_DIR}" -type f)

if [[ "${CHANGES_APPLIED}" -eq 0 ]]; then
  echo "No files to apply. Exiting."
  exit 0
fi

git config user.name "webupd[bot]"
git config user.email "noreply@beyondscalelabs.com"
git commit -m "${PR_TITLE}"

echo "Pushing branch ${BRANCH_NAME}..."
git push origin "${BRANCH_NAME}"

echo "Creating PR..."
GH_TOKEN="${PUSH_TOKEN}" gh pr create \
  --repo "${WEBSITE_REPO}" \
  --base main \
  --head "${BRANCH_NAME}" \
  --title "${PR_TITLE}" \
  --body "${PR_BODY}"

echo "Post-script complete."
