#!/usr/bin/env bash
# Used by the CI "gitops" job: write the freshly pushed image tag into values-dev.yaml.
# Argo CD notices the commit and rolls the cluster forward — CI never touches the cluster.
#   usage: bump-image-tag.sh <tag> [values-file]   (default: the chart's values-dev.yaml)
set -euo pipefail
TAG="${1:?usage: $0 <image-tag> [values-file]}"
VALUES="${2:-$(dirname "$0")/../helm/incidentdesk/values-dev.yaml}"
# replace the tag on the two lines marked as CI-managed; anything else in the file is untouched
sed -E -i.bak "s|^(    tag: )\"[^\"]*\"(  +# updated by the CI \"gitops\" job.*)$|\1\"${TAG}\"\2|" "$VALUES"
rm -f "$VALUES.bak"
n=$(grep -c "tag: \"${TAG}\"" "$VALUES")
[ "$n" -eq 2 ] || { echo "expected 2 tags updated, got $n" >&2; exit 1; }
grep -n 'tag:' "$VALUES"
