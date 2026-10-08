РУБЕЖ — архив проекта для Claude Code на ПК
===========================================

1. Распакуйте папку Rubezh, например в C:\Games\Rubezh (лучше путь без пробелов и кириллицы).

2. Установите (один раз):
   - Godot 4.5 stable, Standard (не .NET): https://godotengine.org/download/archive/4.5-stable/
     файл Godot_v4.5-stable_win64.exe.zip -> распакуйте в C:\Godot\
     (там появится Godot_v4.5-stable_win64_console.exe — он нужен для проверок)
   - Git for Windows: https://git-scm.com/downloads/win
   - Node.js LTS (для MCP-сервера Godot): https://nodejs.org/
   - Claude Code, если ещё не установлен: https://code.claude.com/docs/en/setup

3. Подключите MCP-сервер Godot (один раз). Откройте папку Rubezh в Проводнике, в адресной
   строке наберите cmd и нажмите Enter. В чёрном окне выполните одну строку:

   claude mcp add godot -e GODOT_PATH=C:\Godot\Godot_v4.5-stable_win64_console.exe -- cmd /c npx -y @coding-solo/godot-mcp

   (Если Godot лежит в другой папке — поменяйте путь в команде.)

4. В том же окне наберите claude и нажмите Enter. Первым сообщением вставьте текст из файла
   ПЕРВОЕ_СООБЩЕНИЕ_ДЛЯ_CLAUDE.txt (он лежит рядом и в Rubezh\docs\).
   Дальше Claude сам всё прочитает и продолжит работу по плану из ЭСТАФЕТА.md.

Что внутри:
- Rubezh\ЭСТАФЕТА.md          — главное: что сделано, как запускать, план по шагам, правила
- Rubezh\docs\ТРЕБОВАНИЯ.md   — все ваши сообщения дословно + что из этого уже сделано
- Rubezh\DESIGN.md            — замысел игры
- Rubezh\CLAUDE.md            — правила для Claude Code
- Rubezh\docs\screens\        — скриншоты (было / стало / карта планеты)
- Rubezh\.git\                — вся история изменений

Если после распаковки имена файлов показаны кракозябрами — распакуйте через 7-Zip или WinRAR
(или возьмите ZIP-версию архива).
Тот же код есть на GitHub: Smetanik12/Project, ветка claude/dreamy-dirac-sg8bpf.
