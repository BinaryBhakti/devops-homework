#!/usr/bin/env bash
# Install pinned scanner binaries on a CI runner, verifying the published SHA-256 checksums.
# Release binaries + checksum instead of a third-party wrapper action: after the March 2026
# compromise of the aquasecurity/trivy-action tags, a pinned, verified binary is the safer default.
# usage: install-tools.sh trivy|gitleaks ...
set -euo pipefail
TRIVY_VERSION="${TRIVY_VERSION:-0.75.0}"
GITLEAKS_VERSION="${GITLEAKS_VERSION:-8.30.1}"
tmp=$(mktemp -d)
for tool in "$@"; do
  case "$tool" in
    trivy)
      base="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}"
      file="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"; sums="trivy_${TRIVY_VERSION}_checksums.txt" ;;
    gitleaks)
      base="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}"
      file="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"; sums="gitleaks_${GITLEAKS_VERSION}_checksums.txt" ;;
    *) echo "unknown tool: $tool" >&2; exit 1 ;;
  esac
  curl -sSfL -o "$tmp/$file" "$base/$file"
  curl -sSfL -o "$tmp/$sums" "$base/$sums"
  (cd "$tmp" && sha256sum --check --ignore-missing "$sums")
  sudo tar -xzf "$tmp/$file" -C /usr/local/bin "$tool"
  "$tool" --version | head -1
done
