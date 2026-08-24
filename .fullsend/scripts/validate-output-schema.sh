#!/usr/bin/env bash
# validate-output-schema.sh — Validate agent output against a JSON Schema.
#

set -euo pipefail

echo "Validating output against schema: ${FULLSEND_OUTPUT_SCHEMA}"
