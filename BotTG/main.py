import asyncio
import logging
import os
import sys
from aiohttp import web
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import Command
from aiogram.utils.keyboard import InlineKeyboardBuilder

# Пытаемся импортировать промты
try:
    from prompts import PROMPT_EGE, PROMPT_ITOG, PROMPT_SPORT, PROMPT_COOKING
except ImportError:
    # Если файл не найден, создаем заглушки, чтобы бот не падал
    PROMPT_EGE = "Ошибка: файл prompts.py не найден"
    PROMPT_ITOG = "Ошибка: файл prompts.py не найден"
    PROMPT_SPORT = "Ошибка: файл prompts.py не найден"
    PROMPT_COOKING = "Ошибка: файл prompts.py не найден"

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Твой новый токен
TOKEN = "7982097097:AAHdRqIN_7UC_W57n5R4Irer4cIBcFj8LHM"

bot = Bot(token=TOKEN)
dp = Dispatcher()

# Кэш для реализации "одного окна"
last_messages = {}

async def update_interface(chat_id: int, text: str, reply_markup=None):
    """Обновляет текущее сообщение или присылает новое"""
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
        logger.error(f"Ошибка отправки: {e}")

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
    builder.row(types.InlineKeyboardButton(text="💪 Тренер", callback_data="prompt_sport_coach"))
    builder.row(types.InlineKeyboardButton(text="⬅️ Назад", callback_data="main_menu"))
    return builder.as_markup()

def cooking_menu():
    builder = InlineKeyboardBuilder()
    builder.row(types.InlineKeyboardButton(text="👨‍🍳 Шеф-повар", callback_data="prompt_cooking_uni"))
    builder.row(types.InlineKeyboardButton(text="⬅️ Назад", callback_data="main_menu"))
    return builder.as_markup()

def back_button(target: str):
    builder = InlineKeyboardBuilder()
    builder.row(types.InlineKeyboardButton(text="⬅️ Назад к списку", callback_data=target))
    return builder.as_markup()

# --- ОБРАБОТЧИКИ ---

@dp.message(Command("start"))
async def start_command(message: types.Message):
    await update_interface(
        message.chat.id, 
        "👋 **Выберите категорию:**", 
        main_inline_menu()
    )

@dp.callback_query(F.data == "main_menu")
async def handle_main_menu(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, "Выбери категорию промтов 👇", main_inline_menu())
    await callback.answer()

@dp.callback_query(F.data == "cat_rus")
async def handle_rus(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, "🇷🇺 **Русский язык**", russian_menu())
    await callback.answer()

@dp.callback_query(F.data == "cat_sport")
async def handle_sport(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, "🏋️ **Спорт и Здоровье**", sport_menu())
    await callback.answer()

@dp.callback_query(F.data == "cat_cook")
async def handle_cook(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, "🍳 **Кулинария**", cooking_menu())
    await callback.answer()

# Вывод промтов
@dp.callback_query(F.data == "prompt_ege")
async def send_ege(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, PROMPT_EGE, back_button("cat_rus"))
    await callback.answer()

@dp.callback_query(F.data == "prompt_itog")
async def send_itog(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, PROMPT_ITOG, back_button("cat_rus"))
    await callback.answer()

@dp.callback_query(F.data == "prompt_sport_coach")
async def send_sport(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, PROMPT_SPORT, back_button("cat_sport"))
    await callback.answer()

@dp.callback_query(F.data == "prompt_cooking_uni")
async def send_cooking(callback: types.CallbackQuery):
    await update_interface(callback.message.chat.id, PROMPT_COOKING, back_button("cat_cook"))
    await callback.answer()

# --- WEB SERVER FOR RENDER ---

async def handle_health(request):
    return web.Response(text="OK")

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
