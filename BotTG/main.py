import asyncio
import logging
import os
from aiohttp import web
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import Command
from aiogram.utils.keyboard import InlineKeyboardBuilder
from aiogram.exceptions import TelegramBadRequest

# Твой токен
TOKEN = "7982097097:AAGDEri9jtm_-kSJ9pHn6k5S2GB7BOREKWM"

logging.basicConfig(level=logging.INFO)

bot = Bot(token=TOKEN)
dp = Dispatcher()

# Словарь для хранения ID последнего сообщения бота
last_messages = {}

# --- Вспомогательная функция ---

async def update_interface(chat_id: int, text: str, reply_markup=None):
    """Обновляет текущее сообщение бота или присылает новое, если старое удалено"""
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
        except TelegramBadRequest:
            pass

    # Если редактировать нечего, шлем новое и запоминаем ID
    sent_message = await bot.send_message(
        chat_id=chat_id,
        text=text,
        reply_markup=reply_markup,
        parse_mode="Markdown"
    )
    last_messages[chat_id] = sent_message.message_id

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
    builder.row(types.InlineKeyboardButton(text="💪 Фитнес Тренер", callback_data="prompt_sport_coach"))
    builder.row(types.InlineKeyboardButton(text="⬅️ Назад", callback_data="main_menu"))
    return builder.as_markup()

def cooking_menu():
    builder = InlineKeyboardBuilder()
    builder.row(types.InlineKeyboardButton(text="👨‍🍳 Универсальный рецепт", callback_data="prompt_cooking_uni"))
    builder.row(types.InlineKeyboardButton(text="⬅️ Назад", callback_data="main_menu"))
    return builder.as_markup()

def back_button(target: str):
    builder = InlineKeyboardBuilder()
    builder.row(types.InlineKeyboardButton(text="⬅️ Назад к списку", callback_data=target))
    return builder.as_markup()

# --- ОБРАБОТЧИКИ ---

@dp.message(Command("start"))
async def start_command(message: types.Message):
    # Попытка удалить команду пользователя для чистоты
    try:
        await message.delete()
    except:
        pass
    
    await update_interface(
        message.chat.id, 
        "Привет! Я бот-библиотека промтов.\nВыбери нужный раздел ниже 👇", 
        main_inline_menu()
    )

@dp.callback_query(F.data == "main_menu")
async def handle_main_menu(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, "Выбери нужный раздел ниже 👇", main_inline_menu())
    await callback.answer()

@dp.callback_query(F.data == "cat_rus")
async def handle_rus(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, "🇷🇺 **Русский язык**\nВыбери промт:", russian_menu())
    await callback.answer()

@dp.callback_query(F.data == "cat_sport")
async def handle_sport(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, "🏋️ **Спорт и Здоровье**\nВыбери промт:", sport_menu())
    await callback.answer()

@dp.callback_query(F.data == "cat_cook")
async def handle_cook(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, "🍳 **Кулинария**\nВыбери промт:", cooking_menu())
    await callback.answer()

# --- ВЫДАЧА ПОЛНЫХ ПРОМТОВ ---

@dp.callback_query(F.data == "prompt_ege")
async def send_ege(callback: types.CallbackQuery):
    text = (
        "✅ **ПРОМТ: ЭКСПЕРТ ЕГЭ (СОЧИНЕНИЕ)**\n"
        "```\n"
        "Ты — эксперт ЕГЭ по русскому языку. \n"
        "📌 ЗАДАЧА\n"
        "Напиши сочинение по тексту: [вставить текст]\n\n"
        "❗ ВАЖНО О СТИЛЕ\n"
        "Работу будет проверять учитель русского языка. Поэтому текст должен:\n"
        "- выглядеть как работа реального ученика 10–11 класса\n"
        "- быть естественным, не шаблонным\n"
        "- не содержать «заученных фраз из интернета»\n"
        "- звучать живо, но грамотно\n"
        "- не выглядеть как автоматически сгенерированный текст\n\n"
        "❗ СТРУКТУРА (ОБЯЗАТЕЛЬНО)\n"
        "1 абзац — проблема\n"
        "2 абзац — комментарий (пример 1 + объяснение, пример 2 + объяснение, связь между ними)\n"
        "3 абзац — позиция автора + твоя позиция (согласие/несогласие)\n"
        "4 абзац — литературный аргумент (произведение + краткая ситуация, анализ)\n"
        "5 абзац — вывод\n\n"
        "📏 ОБЪЕМ: 150–200 слов\n"
        "❌ НЕЛЬЗЯ: пересказ текста, фильмы/игры/аниме, личный опыт, шаблоны.\n"
        "📍 ЦЕЛЬ: Максимальный балл на ЕГЭ\n"
        "```"
    )
    await update_interface(callback.message.chat.id, text, back_button("cat_rus"))
    await callback.answer()

@dp.callback_query(F.data == "prompt_itog")
async def send_itog(callback: types.CallbackQuery):
    text = (
        "✅ **ПРОМТ: ИТОГОВОЕ СОЧИНЕНИЕ**\n"
        "```\n"
        "Ты — эксперт по итоговому сочинению. \n"
        "📌 ЗАДАЧА\n"
        "Напиши сочинение на тему: [вставить тему]\n\n"
        "❗ ВАЖНО О СТИЛЕ\n"
        "Текст должен выглядеть как реальное сочинение школьника, быть естественным, не «идеально роботизированным».\n\n"
        "❗ СТРУКТУРА\n"
        "1 абзац — вступление\n"
        "2 абзац — тезис\n"
        "3 абзац — аргумент 1 (произведение + ситуация + анализ)\n"
        "4 абзац — аргумент 2 (другое произведение + анализ)\n"
        "5 абзац — вывод\n\n"
        "📏 ОБЪЕМ: 250–300 слов\n"
        "✔ ТРЕБОВАНИЯ: 2 аргумента из классики, логика, естественный стиль.\n"
        "📍 ЦЕЛЬ: «Зачёт» без проблем\n"
        "```"
    )
    await update_interface(callback.message.chat.id, text, back_button("cat_rus"))
    await callback.answer()

@dp.callback_query(F.data == "prompt_sport_coach")
async def send_sport(callback: types.CallbackQuery):
    text = (
        "🏋️ **ПРОМТ: ФИТНЕС ТРЕНЕР**\n"
        "```\n"
        "Ты — профессиональный фитнес-тренер с опытом более 10 лет. Ты составляешь безопасные, эффективные и реалистичные тренировочные программы под конкретного человека.\n\n"
        "📌 ВХОДНЫЕ ДАННЫЕ:\n"
        "🎯 Цель: [похудение / набор мышечной массы / выносливость / гибкость / общее здоровье]\n"
        "📍 Место тренировок: [дом / улица / тренажёрный зал]\n"
        "🏋️ Инвентарь: [нет оборудования / гантели / турник / штанга / другое]\n"
        "⚠️ Ограничения: [нет / боли в спине / колени / давление / другое]\n"
        "🕒 Уровень подготовки: [новичок / средний / продвинутый]\n\n"
        "🧠 ТРЕБОВАНИЯ К ОТВЕТУ:\n"
        "- Пиши как живой тренер: уверенно, мотивирующе, без «роботности».\n"
        "- Упражнения должны быть безопасными и выполнимыми в реальных условиях.\n"
        "- Если есть ограничения — обязательно учитывай их в технике и выборе упражнений.\n\n"
        "🏋️ СТРУКТУРА ТРЕНИРОВКИ:\n"
        "1. 🔥 РАЗМИНКА (3–6 упражнений): Название, Описание, Цель.\n"
        "2. 💪 ОСНОВНАЯ ЧАСТЬ: Для каждого упр: Название, Подходы, Повторения. Техника выполнения: на что обратить внимание, частые ошибки, как сделать безопасно.\n"
        "3. 🧘 ЗАМИНКА / РАСТЯЖКА: 3–5 упражнений, на какие мышцы, как долго удерживать.\n"
        "4. 🍽 СОВЕТ ПО ПИТАНИЮ: Один конкретный и полезный совет под цель.\n\n"
        "🔥 СТИЛЬ:\n"
        "«Делаем чётко и без халтуры», «Контролируй движение, не гонись за количеством», «Это база твоего результата».\n"
        "```"
    )
    await update_interface(callback.message.chat.id, text, back_button("cat_sport"))
    await callback.answer()

@dp.callback_query(F.data == "prompt_cooking_uni")
async def send_cooking(callback: types.CallbackQuery):
    text = (
        "🍳 **ПРОМТ: КУЛИНАРИЯ - УНИВЕРСАЛЬНЫЙ**\n"
        "```\n"
        "Ты — шеф-повар, обучающий новичка. Составь подробную инструкцию для приготовления: [БЛЮДО].\n\n"
        "1. СПИСОК ПОКУПОК: Что именно нужно купить и в каком количестве.\n"
        "2. ИНВЕНТАРЬ: Какая посуда и техника понадобятся.\n"
        "3. ПОДГОТОВКА: Что нужно помыть, нарезать или разморозить заранее.\n"
        "4. ПОШАГОВОЕ ПРИГОТОВЛЕНИЕ: В виде таблицы или списка (Действие | Время | Огонь/Температура | За чем следить).\n"
        "5. ЧАСТЫЕ ОШИБКИ И ПОДАЧА: Как не испортить и как красиво подать.\n"
        "```"
    )
    await update_interface(callback.message.chat.id, text, back_button("cat_cook"))
    await callback.answer()

# --- Настройка для бесплатного хостинга ---

async def handle_health(request):
    return web.Response(text="I am alive!")

async def start_webserver():
    app = web.Application()
    app.router.add_get("/", handle_health)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", int(os.environ.get("PORT", 8080)))
    await site.start()

async def main():
    print("Starting bot...")
    # Запускаем фоновый веб-сервер для Health Check
    asyncio.create_task(start_webserver())
    # Запускаем бота
    await dp.start_polling(bot)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        print("Bot stopped")