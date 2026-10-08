#!/bin/bash
# Проверка синтаксиса всех скриптов проекта. Печатает ошибки, код выхода 1 — если они есть.
cd "$(dirname "$0")/.."
G=${GODOT:-godot}
fail=0
# обновить реестр class_name (новые классы)
$G --headless --path . --import >/dev/null 2>&1
for f in $(git ls-files '*.gd') $(git ls-files --others --exclude-standard '*.gd'); do
  out=$($G --headless --path . --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error" )
  if [ -n "$out" ]; then echo "== $f"; echo "$out"; fail=1; fi
done
exit $fail
