#!/bin/bash
# Проверка синтаксиса всех скриптов проекта. Печатает ошибки, код выхода 1 — если они есть.
# Godot: переменная GODOT, иначе `godot` из PATH, иначе C:\Godot\Godot_v4.5*_console.exe (Git Bash).
cd "$(dirname "$0")/.."
G=${GODOT:-}
if [ -z "$G" ]; then
  if command -v godot >/dev/null 2>&1; then
    G=godot
  else
    G=$(ls /c/Godot/Godot_v4.5*_console.exe 2>/dev/null | head -n 1)
  fi
fi
if [ -z "$G" ]; then
  echo "Godot не найден: укажите путь, например GODOT=/c/Godot/Godot_v4.5-stable_win64_console.exe tools/check.sh"
  exit 2
fi
fail=0
# обновить реестр class_name (новые классы)
"$G" --headless --path . --import >/dev/null 2>&1
for f in $(git ls-files '*.gd') $(git ls-files --others --exclude-standard '*.gd'); do
  out=$("$G" --headless --path . --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error" )
  if [ -n "$out" ]; then echo "== $f"; echo "$out"; fail=1; fi
done
exit $fail
