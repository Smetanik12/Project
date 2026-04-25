import asyncio
import logging
import os
import sys
from aiohttp import web
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import Command
from aiogram.utils.keyboard import InlineKeyboardBuilder
from aiogram.exceptions import TelegramBadRequest

# Пытаемся импортировать промты
try:
    from prompts import (
        PROMPT_EGE, PROMPT_ITOG, PROMPT_SPORT, 
        PROMPT_COOKING, PROMPT_SMM, PROMPT_RESUME, 
        PROMPT_COVER_LETTER, PROMPT_GAME_HISTORY
    )
except ImportError:
    PROMPT_EGE = PROMPT_ITOG = PROMPT_SPORT = PROMPT_COOKING = PROMPT_SMM = PROMPT_RESUME = PROMPT_COVER_LETTER = PROMPT_GAME_HISTORY = "Ошибка: файл prompts.py не найден"

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TOKEN = "7982097097:AAHdRqIN_7UC_W57n5R4Irer4cIBcFj8LHM"

bot = Bot(token=TOKEN)
dp = Dispatcher()

# Хранилище последних сообщений и блокировки для предотвращения дублирования
last_messages = {}
user_locks = {}

def get_user_lock(chat_id: int):
    """Создает или возвращает замок для конкретного пользователя"""
    if chat_id not in user_locks:
        user_locks[chat_id] = asyncio.Lock()
    return user_locks[chat_id]

async def update_interface(chat_id: int, text: str, reply_markup=None):
    """Обновляет текущее сообщение или присылает новое с защитой от гонки состояний"""
    lock = get_user_lock(chat_id)
    async with lock:
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
            except TelegramBadRequest as e:
                # Если текст совпадает или сообщение не найдено, не паникуем
                if "message is not modified" in str(e):
                    return
                logger.warning(f"Не удалось отредактировать: {e}")
            except Exception as e:
                logger.error(f"Ошибка при правке: {e}")

        # Если не удалось отредактировать или сообщения еще нет — отправляем новое
        try:
            sent_message = await bot.send_message(
                chat_id=chat_id,
                text=text,
                reply_markup=reply_markup,
                parse_mode="Markdown"
            )
            last_messages[chat_id] = sent_message.message_id
        except Exception as e:
            logger.error(f"Ошибка отправки нового сообщения: {e}")

# --- КЛАВИАТУРЫ ---

def main_inline_menu():
    builder = InlineKeyboardBuilder()
    builder.row(types.InlineKeyboardButton(text="🇷🇺 Русский язык", callback_data="cat_rus"))
    builder.row(types.InlineKeyboardButton(text="🍳 Кулинария", callback_data="cat_cook"))
    builder.row(types.InlineKeyboardButton(text="🏋️ Спорт и Здоровье", callback_data="cat_sport"))
    builder.row(types.InlineKeyboardButton(text="💼 Работа", callback_data="cat_work"))
    builder.row(types.InlineKeyboardButton(text="🎮 Игра", callback_data="cat_game"))
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

def work_menu():
    builder = InlineKeyboardBuilder()
    builder.row(types.InlineKeyboardButton(text="📱 SMM-посты", callback_data="prompt_smm"))
    builder.row(types.InlineKeyboardButton(text="📄 Резюме", callback_data="prompt_resume"))
    builder.row(types.InlineKeyboardButton(text="✉️ Сопроводительное письмо", callback_data="prompt_cover"))
    builder.row(types.InlineKeyboardButton(text="⬅️ Назад", callback_data="main_menu"))
    return builder.as_markup()

def game_menu():
    builder = InlineKeyboardBuilder()
    builder.row(types.InlineKeyboardButton(text="🎭 Исторический собеседник", callback_data="prompt_history"))
    builder.row(types.InlineKeyboardButton(text="⬅️ Назад", callback_data="main_menu"))
    return builder.as_markup()

def back_button(target: str):
    builder = InlineKeyboardBuilder()
    builder.row(types.InlineKeyboardButton(text="⬅️ Назад к списку", callback_data=target))
    return builder.as_markup()

# --- ОБРАБОТЧИКИ ---

@dp.message(Command("start"))
async def start_command(message: types.Message):
    await update_interface(message.chat.id, "👋 **Выберите категорию:**", main_inline_menu())

@dp.callback_query(F.data == "main_menu")
async def handle_main_menu(callback: types.CallbackQuery):
    await callback.answer() # Сразу убираем состояние загрузки у кнопки
    await update_interface(callback.message.chat.id, "Выберите категорию 👇", main_inline_menu())

@dp.callback_query(F.data == "cat_rus")
async def handle_rus(callback: types.CallbackQuery):
    await callback.answer()
    await update_interface(callback.message.chat.id, "🇷🇺 **Русский язык**", russian_menu())

@dp.callback_query(F.data == "cat_sport")
async def handle_sport(callback: types.CallbackQuery):
    await callback.answer()
    await update_interface(callback.message.chat.id, "🏋️ **Спорт и Здоровье**", sport_menu())

@dp.callback_query(F.data == "cat_cook")
async def handle_cook(callback: types.CallbackQuery):
    await callback.answer()
    await update_interface(callback.message.chat.id, "🍳 **Кулинария**", cooking_menu())

@dp.callback_query(F.data == "cat_work")
async def handle_work(callback: types.CallbackQuery):
    await callback.answer()
    await update_interface(callback.message.chat.id, "💼 **Работа**", work_menu())

@dp.callback_query(F.data == "cat_game")
async def handle_game(callback: types.CallbackQuery):
    await callback.answer()
    await update_interface(callback.message.chat.id, "🎮 **Игра**", game_menu())

# Вывод промтов
@dp.callback_query(F.data == "prompt_ege")
async def send_ege(callback: types.CallbackQuery):
    await callback.answer()
    await update_interface(callback.message.chat.id, PROMPT_EGE, back_button("cat_rus"))

@dp.callback_query(F.data == "prompt_itog")
async def send_itog(callback: types.CallbackQuery):
    await callback.answer()
    await update_interface(callback.message.chat.id, PROMPT_ITOG, back_button("cat_rus"))

@dp.callback_query(F.data == "prompt_sport_coach")
async def send_sport(callback: types.CallbackQuery):
    await callback.answer()
    await update_interface(callback.message.chat.id, PROMPT_SPORT, back_button("cat_sport"))

@dp.callback_query(F.data == "prompt_cooking_uni")
async def send_cooking(callback: types.CallbackQuery):
    await callback.answer()
    await update_interface(callback.message.chat.id, PROMPT_COOKING, back_button("cat_cook"))

@dp.callback_query(F.data == "prompt_smm")
async def send_smm(callback: types.CallbackQuery):
    await callback.answer()
    await update_interface(callback.message.chat.id, PROMPT_SMM, back_button("cat_work"))

@dp.callback_query(F.data == "prompt_resume")
async def send_resume(callback: types.CallbackQuery):
    await callback.answer()
    await update_interface(callback.message.chat.id, PROMPT_RESUME, back_button("cat_work"))

@dp.callback_query(F.data == "prompt_cover")
async def send_cover(callback: types.CallbackQuery):
    await callback.answer()
    await update_interface(callback.message.chat.id, PROMPT_COVER_LETTER, back_button("cat_work"))

@dp.callback_query(F.data == "prompt_history")
async def send_history(callback: types.CallbackQuery):
    await callback.answer()
    await update_interface(callback.message.chat.id, PROMPT_GAME_HISTORY, back_button("cat_game"))

# --- WEB SERVER FOR RENDER ---

async def handle_health(request):
    return web.Response(text="OK")

async def main():
    app = web.Application()
    app.router.add_get("/", handle_health)
    runner = web.AppRunner(app)
    await runner.setup()
    port = int(os.environ.get("PORT", 8080))
    site = web.TCPSite(runner, "0.0.0.0", port)
    await site.start()
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
