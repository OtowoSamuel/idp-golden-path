#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
for module in terraform-modules/*/; do
  name=$(basename "$module")
  echo "=== $name ==="
  (
    cd "$module"
    terraform init -backend=false -input=false -no-color >/dev/null 2>&1
    terraform validate -no-color
    terraform test -no-color
  ) || fail=1
done

exit $fail
