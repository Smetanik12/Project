РУБЕЖ — архив проекта для Claude Code на ПК
===========================================

1. Распакуйте папку Rubezh, например в C:\Games\Rubezh (путь без кириллицы надёжнее для
   инструментов, но Godot работает и с кириллицей).
2. Установите Godot 4.5 stable (Standard, не .NET):
   https://godotengine.org/download/archive/4.5-stable/  → распакуйте в C:\Godot\
3. Установите Node.js 18+ (для MCP-сервера Godot): https://nodejs.org/
4. Откройте папку Rubezh в Claude Code и вставьте текст из
   Rubezh\docs\ПЕРВОЕ_СООБЩЕНИЕ_ДЛЯ_CLAUDE.txt — дальше Claude всё сделает по ЭСТАФЕТА.md.
5. Подключить MCP для Godot (один раз, в PowerShell в папке Rubezh):
   claude mcp add godot -e GODOT_PATH="C:\Godot\Godot_v4.5-stable_win64_console.exe" -- npx -y @coding-solo/godot-mcp

Что внутри:
- Rubezh\ЭСТАФЕТА.md          — главное: состояние, план, инструкции, правила
- Rubezh\docs\ТРЕБОВАНИЯ.md   — все ваши сообщения дословно + сводка со статусом
- Rubezh\DESIGN.md            — замысел игры
- Rubezh\CLAUDE.md            — правила для Claude Code
- Rubezh\docs\screens\        — скриншоты (было / стало / карта планеты)
- Rubezh\.git\                — вся история изменений (git log)

Тот же код есть на GitHub: Smetanik12/Project, ветка claude/dreamy-dirac-sg8bpf.
