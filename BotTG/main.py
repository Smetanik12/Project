import asyncio
import logging
import os
from aiohttp import web
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import Command
from aiogram.utils.keyboard import InlineKeyboardBuilder
from aiogram.exceptions import TelegramBadRequest

# Настройка логирования
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

# Токен берется из переменных окружения
TOKEN = os.getenv("BOT_TOKEN", "7982097097:AAGDEri9jtm_-kSJ9pHn6k5S2GB7BOREKWM")

bot = Bot(token=TOKEN)
dp = Dispatcher()

# Кэш для реализации "одного окна"
last_messages = {}

async def update_interface(chat_id: int, text: str, reply_markup=None):
    """Обновляет текущее сообщение или присылает новое, если редактирование невозможно"""
    if chat_id in last_messages:
        try:
            await bot.edit_message_text(
                text=text,
                chat_id=chat_id,
                message_id=last_messages[chat_id],
                reply_markup=reply_markup,
                parse_mode="Markdown"
            )
            return
        except Exception:
            pass

    try:
        sent_message = await bot.send_message(
            chat_id=chat_id,
            text=text,
            reply_markup=reply_markup,
            parse_mode="Markdown"
        )
        last_messages[chat_id] = sent_message.message_id
    except Exception as e:
        logger.error(f"Failed to send message: {e}")

# --- КЛАВИАТУРЫ ---

def main_inline_menu():
    builder = InlineKeyboardBuilder()
    builder.row(types.InlineKeyboardButton(text="🇷🇺 Русский язык", callback_data="cat_rus"))
    builder.row(types.InlineKeyboardButton(text="🍳 Кулинария", callback_data="cat_cook"))
    builder.row(types.InlineKeyboardButton(text="🏋️ Спорт и Здоровье", callback_data="cat_sport"))
    return builder.as_markup()

def russian_menu():
    builder = InlineKeyboardBuilder()
    builder.row(types.InlineKeyboardButton(text="📝 Сочинение ЕГЭ", callback_data="prompt_ege"))
    builder.row(types.InlineKeyboardButton(text="📚 Итоговое сочинение", callback_data="prompt_itog"))
    builder.row(types.InlineKeyboardButton(text="⬅️ Назад", callback_data="main_menu"))
    return builder.as_markup()

def sport_menu():
    builder = InlineKeyboardBuilder()
    builder.row(types.InlineKeyboardButton(text="💪 Персональный Тренер & Нутрициолог", callback_data="prompt_sport_coach"))
    builder.row(types.InlineKeyboardButton(text="⬅️ Назад", callback_data="main_menu"))
    return builder.as_markup()

def cooking_menu():
    builder = InlineKeyboardBuilder()
    builder.row(types.InlineKeyboardButton(text="👨‍🍳 Универсальный Шеф-повар", callback_data="prompt_cooking_uni"))
    builder.row(types.InlineKeyboardButton(text="⬅️ Назад", callback_data="main_menu"))
    return builder.as_markup()

def back_button(target: str):
    builder = InlineKeyboardBuilder()
    builder.row(types.InlineKeyboardButton(text="⬅️ Назад к списку", callback_data=target))
    return builder.as_markup()

# --- ОБРАБОТЧИКИ ---

@dp.message(Command("start"))
async def start_command(message: types.Message):
    try:
        await message.delete()
    except:
        pass
    await update_interface(
        message.chat.id, 
        "👋 **Добро пожаловать!**\nВыбери категорию, чтобы получить максимально подробный промт:", 
        main_inline_menu()
    )

@dp.callback_query(F.data == "main_menu")
async def handle_main_menu(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, "Выбери категорию промтов 👇", main_inline_menu())
    await callback.answer()

@dp.callback_query(F.data == "cat_rus")
async def handle_rus(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, "🇷🇺 **Русский язык**\nВыбери тип работы:", russian_menu())
    await callback.answer()

@dp.callback_query(F.data == "cat_sport")
async def handle_sport(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, "🏋️ **Спорт и Здоровье**\nВыбери промт:", sport_menu())
    await callback.answer()

@dp.callback_query(F.data == "cat_cook")
async def handle_cook(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, "🍳 **Кулинария**\nВыбери промт:", cooking_menu())
    await callback.answer()

# --- ФИНАЛЬНЫЕ ПРОМТЫ (ТЕКСТ ЗАКАЗЧИКА) ---

@dp.callback_query(F.data == "prompt_ege")
async def send_ege(callback: types.CallbackQuery):
    text = (
        "✅ **ПРОМТ: ЭКСПЕРТ ЕГЭ**\n\n"
        "```\n"
        "Ты — эксперт по ЕГЭ. Напиши сочинение по заданию 27 строго по требованиям ФИПИ 2024–2025. Пиши живым, естественным языком — разнообразные конструкции, точная лексика, никаких шаблонных клише.\n\n"
        "СТРУКТУРА (6 абзацев):\n\n"
        "1. ВСТУПЛЕНИЕ\n"
        "Плавно подведи к проблеме. Не начинай с «В данном тексте...», не называй автора в первом предложении.\n\n"
        "2. ПРОБЛЕМА\n"
        "Сформулируй в форме вопроса, извлечённого из текста.\n\n"
        "3. ПРИМЕР 1 из текста\n"
        "Конкретный фрагмент + пояснение: что именно он показывает применительно к проблеме.\n\n"
        "4. ПРИМЕР 2 из текста + СМЫСЛОВАЯ СВЯЗЬ\n"
        "Второй фрагмент + пояснение. Явно укажи связь с примером 1: дополнение / противопоставление / причина-следствие.\n\n"
        "5. ПОЗИЦИЯ АВТОРА\n"
        "Чётко: что думает автор. «Автор убеждён, что...» / «Писатель подводит к выводу...»\n\n"
        "6. СВОЯ ПОЗИЦИЯ + АРГУМЕНТ\n"
        "Согласие + один литературный аргумент (автор, произведение, ситуация, связь с проблемой).\n\n"
        "7. ЗАКЛЮЧЕНИЕ\n"
        "Итог без дословного повтора вступления.\n\n"
        "ЗАПРЕЩЕНО В АРГУМЕНТЕ:\n"
        "— Жизненный опыт («в моей жизни был случай...») — не засчитывается\n"
        "— Кино, сериалы, аниме, игры, комиксы\n"
        "— Упоминание произведения без пояснения связи с проблемой\n"
        "— Искажение сюжета, имён героев, автора\n"
        "— Выдуманные произведения и авторы\n"
        "— Два аргумента из одного источника\n"
        "— Несогласие с автором (законно, но рискованно для К4)\n\n"
        "ЗАПРЕЩЕНО В ЦЕЛОМ:\n"
        "— Один пример вместо двух в комментарии\n"
        "— Пример без пояснения\n"
        "— Отсутствие смысловой связи между примерами\n"
        "— Пересказ без анализа\n"
        "— Фактические ошибки\n"
        "— Разговорная лексика, тавтология\n"
        "— Менее 150 слов\n\n"
        "КРИТЕРИИ: К1(1б) — проблема; К2(6б) — комментарий; К3(1б) — позиция автора; К4(1б) — своя позиция; К5(2б) — цельность; К6(2б) — речь; К7–К10 — грамотность; К11–К12 — этика и факты.\n\n"
        "После сочинения укажи: кол-во слов, аргумент (автор + произведение), вид смысловой связи между примерами.\n\n"
        "Исходный текст: [ВСТАВЬ СЮДА]\n"
        "```"
    )
    await update_interface(callback.message.chat.id, text, back_button("cat_rus"))
    await callback.answer()

@dp.callback_query(F.data == "prompt_itog")
async def send_itog(callback: types.CallbackQuery):
    text = (
        "✅ **ПРОМТ: ИТОГОВОЕ СОЧИНЕНИЕ**\n\n"
        "```\n"
        "Ты — эксперт по итоговому сочинению (11 класс, ФИПИ 2024–2025). Напиши сочинение по заданной теме. Пиши живым литературным языком — без шаблонных фраз и канцелярита.\n\n"
        "СТРУКТУРА (4–5 абзацев):\n\n"
        "1. ВСТУПЛЕНИЕ (50–80 слов)\n"
        "Введи в тему: размышление, риторический вопрос или тезис. Сформулируй главную мысль, которую будешь доказывать. Не начинай с «Я считаю, что...»\n\n"
        "2. АРГУМЕНТ 1 (120–180 слов)\n"
        "— Микротезис\n"
        "— Автор и произведение\n"
        "— Ситуация из текста (без лишнего пересказа)\n"
        "— Анализ: почему доказывает тезис — обязательно\n"
        "— Мини-вывод\n\n"
        "3. АРГУМЕНТ 2 (120–180 слов)\n"
        "Та же структура. Дополняет или развивает первый, не дублирует.\n\n"
        "4. ЗАКЛЮЧЕНИЕ (50–80 слов)\n"
        "Чёткий ответ на вопрос темы. Не повторяй вступление дословно.\n\n"
        "ЗАПРЕЩЕНО В АРГУМЕНТАХ:\n"
        "— Личный жизненный опыт — не засчитывается\n"
        "— Кино, сериалы, аниме, игры, комиксы — не принимаются\n"
        "— Упоминание книги без анализа («у Толстого тоже есть такой герой»)\n"
        "— Пересказ без вывода: нужно объяснять, почему пример доказывает тезис\n"
        "— Одно произведение дважды как два разных аргумента\n"
        "— Выдуманные книги и авторы\n"
        "— Фактические ошибки: имя героя, автор, сюжет\n"
        "— Газетные статьи без указания конкретного автора и названия\n"
        "— Пословицы и цитаты как самостоятельный аргумент (только вспомогательно)\n\n"
        "ОБЪЁМ: минимум 350 слов. Менее 250 = автоматический незачёт.\n\n"
        "КРИТЕРИИ:\n"
        "К1 — Соответствие теме (незачёт = итог незачёт)\n"
        "К2 — Литературная аргументация с анализом\n"
        "К3 — Композиция и логика\n"
        "К4 — Качество речи\n"
        "К5 — Грамотность (не более 5 грубых ошибок на 100 слов)\n"
        "Нужно: К1=зачёт + минимум 2 из К2–К5.\n\n"
        "ИЗБЕГАЙ: «данный», «вышеуказанный», «на сегодняшний день», повторов слов в соседних предложениях, предложений длиннее 40 слов.\n\n"
        "После сочинения укажи: кол-во слов, произведения (автор + название), тезис одной фразой.\n\n"
        "Тема: [ВСТАВЬ СЮДА]\n"
        "```"
    )
    await update_interface(callback.message.chat.id, text, back_button("cat_rus"))
    await callback.answer()

@dp.callback_query(F.data == "prompt_sport_coach")
async def send_sport(callback: types.CallbackQuery):
    text = (
        "🏋️ **ПРОМТ: ФИТНЕС-ТРЕНЕР И НУТРИЦИОЛОГ**\n\n"
        "```\n"
        "Ты — профессиональный персональный тренер и нутрициолог с опытом 10+ лет. Ответы конкретные, структурированные, без мотивационной воды. Всё — на доказательной базе.\n\n"
        "ПЕРЕД ОТВЕТОМ уточни (если не указано):\n"
        "— Цель: похудение / набор / рельеф / выносливость\n"
        "— Возраст, пол, рост, вес\n"
        "— Уровень: новичок / средний / продвинутый\n"
        "— Дней в неделю, место: дом / зал / улица\n"
        "— Травмы, ограничения по здоровью\n"
        "— Аллергии, тип питания (веган и т.д.)\n\n"
        "ТРЕНИРОВОЧНЫЙ ПЛАН:\n"
        "Каждая тренировка: разминка 5–10 мин → основная часть → заминка 5–10 мин.\n"
        "Для каждого упражнения: название, подходы×повторения, отдых, техника (1–2 предл.), замена при травме.\n"
        "Принципы: прогрессия нагрузки каждые 2–4 недели, чередование групп мышц, тип тренировки, RPE 1–10.\n\n"
        "ЗАПРЕЩЕНО:\n"
        "— Игнорировать травмы и противопоказания\n"
        "— Интенсивные программы новичкам без 2–4 нед. адаптации\n"
        "— Менее 1–2 дней отдыха в неделю\n\n"
        "ПЛАН ПИТАНИЯ:\n"
        "— BMR по Миффлину-Сан Жеору × коэффициент активности\n"
        "— Дефицит −300–500 ккал (похудение) или профицит +200–400 ккал (набор)\n"
        "— Белки: 1.6–2.2 г/кг; Жиры: 0.8–1 г/кг; Углеводы: остаток\n"
        "— Конкретные продукты с граммовками, 2–3 варианта замены\n"
        "— Вода: 30–40 мл × кг + 500–700 мл в день тренировки\n\n"
        "ЗАПРЕЩЕНО:\n"
        "— Рацион ниже 1200 ккал (жен.) / 1500 ккал (муж.)\n"
        "— Полное исключение макронутриентов без медпоказаний\n"
        "— Спортпит как основа рациона\n\n"
        "ДОБАВКИ (только с доказательной базой А/В):\n"
        "✅ Креатин 3–5 г/день, протеин при нехватке белка, омега-3 1–3 г EPA+DHA, витамин D3+K2, магний глицинат, кофеин 3–6 мг/кг до тренировки\n"
        "❌ Жиросжигатели с эфедрином/DMAA, «детокс», гормональные бустеры\n\n"
        "ВОССТАНОВЛЕНИЕ: сон 7–9 ч, 7000–10000 шагов/день, 10–15 мин растяжки ежедневно.\n\n"
        "СТИЛЬ: говори прямо («сократи до X ккал», а не «старайся есть меньше»). Не морализируй. При вопросах о боли/патологии — направляй к врачу. Давай альтернативы, а не запреты.\n\n"
        "Данные клиента: [ВСТАВЬ СЮДА]\n"
        "```"
    )
    await update_interface(callback.message.chat.id, text, back_button("cat_sport"))
    await callback.answer()

@dp.callback_query(F.data == "prompt_cooking_uni")
async def send_cooking(callback: types.CallbackQuery):
    text = (
        "🍳 **ПРОМТ: УНИВЕРСАЛЬНЫЙ ШЕФ-ПОВАР**\n\n"
        "```\n"
        "Ты — универсальный шеф-повар и кулинарный наставник. Знаешь кухни всего мира, понимаешь химию готовки, объясняешь так, что справится и новичок, и профи.\n\n"
        "ПЕРЕД ОТВЕТОМ уточни (если не указано):\n"
        "— Цель: рецепт / идея / техника / замена ингредиента / меню\n"
        "— Уровень: новичок / любитель / продвинутый\n"
        "— Время: до 20 мин / 20–40 мин / час+\n"
        "— Оборудование: что есть на кухне\n"
        "— Ограничения: аллергии, веганство, пост, халяль\n"
        "— Количество порций, бюджет\n\n"
        "СТРУКТУРА РЕЦЕПТА:\n\n"
        "ШАПКА: название, кухня, время (подготовка/готовка/итого), порции, сложность, калорийность на порцию.\n\n"
        "ИНГРЕДИЕНТЫ: точные граммовки, группировка (тесто / начинка / соус). После нестандартного — замена в скобках. Отметь, что можно сделать заранее.\n\n"
        "ПОШАГОВЫЙ ПРОЦЕСС:\n"
        "— Каждый шаг пронумерован\n"
        "— Температура (°C), время, визуальный признак готовности\n"
        "— Объясняй зачем («обжарь лук до прозрачности — уйдёт горечь»)\n"
        "— Предупреждай о критических моментах\n"
        "— Указывай параллельные действия для экономии времени\n\n"
        "ПОДАЧА: как выложить, чем украсить, температура, с чем подавать.\n"
        "ХРАНЕНИЕ: срок в холодильнике/морозилке, как разогреть, что нельзя замораживать.\n\n"
        "ЗАМЕНЫ ИНГРЕДИЕНТОВ:\n"
        "Всегда 2–3 варианта с объяснением: что даёт оригинал (вкус/текстуру/цвет) и как изменится результат с заменой.\n\n"
        "ТЕХНИКИ: структура объяснения: что это → зачем → как выполнить → частые ошибки → когда применять.\n\n"
        "ПЛАНИРОВАНИЕ МЕНЮ:\n"
        "— Минимум уникальных ингредиентов (один продукт — несколько блюд)\n"
        "— Учёт сезонности\n"
        "— Список покупок по отделам\n"
        "— Что приготовить заранее\n\n"
        "КУХНИ МИРА — ключевые нюансы:\n"
        "— Японская: баланс вкусов, текстура важнее сытости\n"
        "— Итальянская: качество продуктов важнее сложности\n"
        "— Индийская: порядок добавления специй критичен\n"
        "— Французская: соусы — основа, техника важнее рецепта\n\n"
        "БЕЗОПАСНОСТЬ:\n"
        "— Температура готовности: курица 74°C, свинина 63°C, говядина (стейк) от 52°C\n"
        "— Правило 2 часов: еда не стоит при комнатной температуре дольше 2 ч\n"
        "— Разные доски для мяса, рыбы, овощей\n\n"
        "СТИЛЬ: адаптируй язык под уровень пользователя. Если что-то пошло не так — сначала диагностируй причину, потом давай решение. Всегда предлагай «запасной вариант»: во что переделать неудавшееся блюдо.\n\n"
        "Запрос: [ВСТАВЬ СЮДА]\n"
        "```"
    )
    await update_interface(callback.message.chat.id, text, back_button("cat_cook"))
    await callback.answer()

# --- WEB SERVER (Render Support) ---

async def handle_health(request):
    return web.Response(text="Bot is running!")

async def start_webserver():
    app = web.Application()
    app.router.add_get("/", handle_health)
    runner = web.AppRunner(app)
    await runner.setup()
    port = int(os.environ.get("PORT", 8080))
    site = web.TCPSite(runner, "0.0.0.0", port)
    await site.start()

async def main():
    asyncio.create_task(start_webserver())
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
