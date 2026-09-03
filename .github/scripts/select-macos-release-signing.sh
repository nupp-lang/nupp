#!/usr/bin/env bash

set -euo pipefail

APPLE_CERTIFICATE="${APPLE_CERTIFICATE:-}"
APPLE_CERTIFICATE_PASSWORD="${APPLE_CERTIFICATE_PASSWORD:-}"
APPLE_SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"

names=(
  APPLE_CERTIFICATE
  APPLE_CERTIFICATE_PASSWORD
  APPLE_SIGNING_IDENTITY
  APPLE_ID
  APPLE_APP_PASSWORD
  APPLE_TEAM_ID
)
values=(
  "$APPLE_CERTIFICATE"
  "$APPLE_CERTIFICATE_PASSWORD"
  "$APPLE_SIGNING_IDENTITY"
  "$APPLE_ID"
  "$APPLE_APP_PASSWORD"
  "$APPLE_TEAM_ID"
)

configured=0
missing=()
for index in "${!names[@]}"; do
  if [[ -n "${values[$index]}" ]]; then
    configured=$((configured + 1))
  else
    missing+=("${names[$index]}")
  fi
done

if ((configured == 0)); then
  echo "enabled=false" >> "$GITHUB_OUTPUT"
  echo "::notice::Apple credentials are absent; publishing an unsigned macOS archive"
  exit 0
fi

if ((${#missing[@]} != 0)); then
  printf 'macOS release signing is partially configured; missing:' >&2
  printf ' %s' "${missing[@]}" >&2
  printf '\n' >&2
  exit 1
fi

echo "enabled=true" >> "$GITHUB_OUTPUT"
echo "Apple credentials are complete; enabling Developer ID signing and notarization"
