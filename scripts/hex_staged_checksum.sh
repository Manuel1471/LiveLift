#!/bin/sh
set -eu

checksum=$(sed -nE 's/^Package SHA-256: ([0-9a-f]{64})$/\1/p' "$1")
if ! printf '%s\n' "$checksum" | awk 'END {exit !(NR == 1 && length($0) == 64)}'; then
  echo "Expected one SHA-256 for the package staged on Hex" >&2
  exit 1
fi

printf '%s\n' "$checksum"
