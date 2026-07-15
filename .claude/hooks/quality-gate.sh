#!/bin/bash

INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

ERRORS=""

# Lint check
if ! nix run .#lint 2>&1; then
  ERRORS="${ERRORS}Lint Error.\n"
fi

# Test
if ! nix run .#test 2>&1; then
  ERRORS="${ERRORS}Test Error.\n"
fi

if [ -n "$ERRORS" ]; then
  echo -e "$ERRORS" >&2
  exit 2
fi

exit 0
