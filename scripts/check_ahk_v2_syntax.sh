#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Heuristic checks for common AutoHotkey v1-only command syntax.
# This is not a full parser, but it catches accidental regressions quickly.
patterns=(
  '^[[:space:]]*MsgBox[[:space:]]*,'
  '^[[:space:]]*SetTimer[[:space:]]*,'
  '^[[:space:]]*PixelGetColor[[:space:]]*,'
  '^[[:space:]]*Sleep[[:space:]]+[0-9]+'
  '^[[:space:]]*Process[[:space:]]*,'
  '^[[:space:]]*String(TrimLeft|TrimRight|Lower|Upper|Len|Split|Replace)\b'
  '^[[:space:]]*IfWin(Exist|Active|NotActive)\b'
  '^[[:space:]]*Win(Activate|Wait|WaitActive|WaitNotActive|Close|Kill)\b'
  '^[[:space:]]*Gui[[:space:]]*,'
  '^[[:space:]]*Send[[:space:]]*,'
  '^[[:space:]]*ControlClick[[:space:]]*,'
)

status=0
while IFS= read -r file; do
  for pattern in "${patterns[@]}"; do
    if rg -n "$pattern" "$file" >/dev/null; then
      echo "Potential AutoHotkey v1 syntax found in $file (pattern: $pattern)"
      rg -n "$pattern" "$file" || true
      status=1
    fi
  done
done < <(rg --files -g '*.ahk')

if [[ $status -ne 0 ]]; then
  echo "AutoHotkey v2 compliance check failed."
  exit 1
fi

echo "AutoHotkey v2 compliance check passed."
