#!/usr/bin/env bash
set -euo pipefail

# Stage only the static frameworks referenced by Package.swift. Do not depend on
# a developer's old Xcode products or copy the entire derived-data directory.
[[ $# -eq 3 ]] || {
  echo "Usage: $0 <build-products-directory> <destination-directory> <arm64|x86_64>" >&2
  exit 1
}
products_dir="$1"
destination_dir="$2"
build_arch="$3"
case "$build_arch" in
  arm64|x86_64) ;;
  *) echo "Unsupported cmux link architecture: $build_arch" >&2; exit 1 ;;
esac

# Validate all inputs before replacing any previously prepared dependency.
for framework in Sentry Iroh; do
  binary="$products_dir/$framework.framework/$framework"
  [[ -f "$binary" ]] || {
    echo "Missing cmux link dependency: $binary" >&2
    exit 1
  }
  lipo -verify_arch "$build_arch" "$binary" || {
    echo "cmux link dependency does not support $build_arch: $binary" >&2
    exit 1
  }
done

mkdir -p "$destination_dir"
staging_dir="$(mktemp -d "$destination_dir/.link-dependencies.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
for framework in Sentry Iroh; do
  ditto "$products_dir/$framework.framework" "$staging_dir/$framework.framework"
done
for framework in Sentry Iroh; do
  rm -rf "$destination_dir/$framework.framework"
  mv "$staging_dir/$framework.framework" "$destination_dir/$framework.framework"
done
echo "Prepared cmux link dependencies ($build_arch): $destination_dir"
