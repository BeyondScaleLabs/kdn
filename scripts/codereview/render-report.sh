#!/usr/bin/env bash
#
# Copyright (C) 2026 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

# Renders the AI code review result into a GitHub check-run payload and a PR comment.
# Usage: render-report.sh <review-result.json> <output-dir>
# Writes <output-dir>/check.json (PATCH body for the check run) and <output-dir>/comment.md.
# The review text is model output, so it is untrusted: mentions are neutralised,
# HTML comments are escaped (the sticky-comment marker cannot be forged) and size is capped.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <review-result.json> <output-dir>" >&2
  exit 2
fi

result=$1
out=$2
mkdir -p "$out"

jq --arg marker '<!-- ai-code-review -->' '
  def sanitize:
    gsub("@(?<c>[A-Za-z0-9])"; "@\u200b\(.c)")
    | gsub("<!--"; "&lt;!--")
    | if length > 60000 then .[0:60000] + "\n\n…(truncated)" else . end;
  def usd: (. * 100 | round) as $c | "$\($c / 100 | floor).\($c % 100 | tostring | if length < 2 then "0" + . else . end)";

  (if .usage then (.usage.cost_usd | usd) else "n/a" end) as $cost
  | (.comments | tostring | sanitize) as $review
  | (if .failed then {conclusion: "failure", title: "⚠️ Review failed or timed out"}
     elif .status == "ACCEPT" then {conclusion: "success", title: "✅ Approved"}
     elif .status == "ACCEPT_WITH_NITS" then {conclusion: "neutral", title: "🟡 Approved with nits"}
     else {conclusion: "failure", title: "❌ Changes requested"} end) as $s
  | ([
      "## \($s.title)",
      "",
      "| | |",
      "|---|---|",
      "| Pull request | #\(.pr_number) |",
      "| Commit | `\(.head_sha[0:7])` |",
      "| Model | `\(.model)` |",
      "| Status | `\(.status)` |",
      "| Duration | \(.duration_s)s |",
      "| Estimated cost | \($cost) |",
      (if .usage then "| Tokens | in \(.usage.input_tokens) · out \(.usage.output_tokens) · cache read \(.usage.cache_read_tokens) · cache write \(.usage.cache_write_tokens) (\(.usage.num_turns) turns) |" else empty end),
      "| Timed out | \(if .timed_out then "yes" else "no" end) |",
      "| Run | [workflow logs](\(.run_url)) |",
      "",
      "> AI review is advisory: a maintainer still has to review and approve this PR."
    ] | join("\n")) as $summary
  | {
      check: {
        status: "completed",
        conclusion: $s.conclusion,
        output: {title: $s.title, summary: $summary, text: $review}
      },
      comment: ([
        $marker,
        "### AI code review: \($s.title) for commit `\(.head_sha[0:7])`",
        "",
        $review,
        "",
        "---",
        "<sub>Model `\(.model)` · estimated cost \($cost) · [Run details](\(.run_url)). AI review is advisory.</sub>"
      ] | join("\n"))
    }
' "$result" > "$out/rendered.json"

jq '.check' "$out/rendered.json" > "$out/check.json"
jq -r '.comment' "$out/rendered.json" > "$out/comment.md"
rm "$out/rendered.json"
