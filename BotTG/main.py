import asyncio
import logging
import os
from aiohttp import web
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import Command
from aiogram.utils.keyboard import InlineKeyboardBuilder
from aiogram.exceptions import TelegramBadRequest
from aiogram.fsm.context import FSMContext # Добавили для сброса состояний

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

# Твой токен
TOKEN = "7982097097:AAHBNsw-pPdXWeOjjD_XNs93ls1xpx0JH5s"

bot = Bot(token=TOKEN)
dp = Dispatcher()

# Хранилище последних сообщений и блокировки
last_messages = {}
user_locks = {}

def get_user_lock(chat_id: int):
    if chat_id not in user_locks:
        user_locks[chat_id] = asyncio.Lock()
    return user_locks[chat_id]

async def update_interface(chat_id: int, text: str, reply_markup=None):
    """Обновляет текущее сообщение или присылает новое, если старое удалено"""
    lock = get_user_lock(chat_id)
    async with lock:
        success = False
        if chat_id in last_messages:
            try:
                # Пытаемся отредактировать
                await bot.edit_message_text(
                    text=text,
                    chat_id=chat_id,
                    message_id=last_messages[chat_id],
                    reply_markup=reply_markup,
                    parse_mode="Markdown"
                )
                success = True
            except Exception as e:
                # Если сообщение удалено пользователем (очистка чата), 
                # редактирование всегда выдаст ошибку.
                logger.info(f"Редактирование не удалось (возможно, чат очищен): {e}")
                success = False

        # Если редактирование не получилось (success == False), отправляем НОВОЕ сообщение
        if not success:
            try:
                sent_message = await bot.send_message(
                    chat_id=chat_id,
                    text=text,
                    reply_markup=reply_markup,
                    parse_mode="Markdown"
                )
                last_messages[chat_id] = sent_message.message_id
            except Exception as e:
                logger.error(f"Критическая ошибка отправки: {e}")

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
async def start_command(message: types.Message, state: FSMContext):
    await state.clear() # Сбрасываем всё, чтобы бот точно увидел команду
    await update_interface(message.chat.id, "👋 **Выберите категорию:**", main_inline_menu())

@dp.callback_query(F.data == "main_menu")
async def handle_main_menu(callback: types.CallbackQuery, state: FSMContext):
    await state.clear()
    await callback.answer()
    await update_interface(callback.message.chat.id, "Выберите категорию 👇", main_inline_menu())

# Группы кнопок
@dp.callback_query(F.data.startswith("cat_"))
async def categories_handler(callback: types.CallbackQuery):
    await callback.answer()
    if callback.data == "cat_rus":
        await update_interface(callback.message.chat.id, "🇷🇺 **Русский язык**", russian_menu())
    elif callback.data == "cat_sport":
        await update_interface(callback.message.chat.id, "🏋️ **Спорт и Здоровье**", sport_menu())
    elif callback.data == "cat_cook":
        await update_interface(callback.message.chat.id, "🍳 **Кулинария**", cooking_menu())
    elif callback.data == "cat_work":
        await update_interface(callback.message.chat.id, "💼 **Работа**", work_menu())
    elif callback.data == "cat_game":
        await update_interface(callback.message.chat.id, "🎮 **Игра**", game_menu())

# Вывод промтов
@dp.callback_query(F.data.startswith("prompt_"))
async def prompts_handler(callback: types.CallbackQuery):
    await callback.answer()
    data = callback.data
    if data == "prompt_ege":
        await update_interface(callback.message.chat.id, PROMPT_EGE, back_button("cat_rus"))
    elif data == "prompt_itog":
        await update_interface(callback.message.chat.id, PROMPT_ITOG, back_button("cat_rus"))
    elif data == "prompt_sport_coach":
        await update_interface(callback.message.chat.id, PROMPT_SPORT, back_button("cat_sport"))
    elif data == "prompt_cooking_uni":
        await update_interface(callback.message.chat.id, PROMPT_COOKING, back_button("cat_cook"))
    elif data == "prompt_smm":
        await update_interface(callback.message.chat.id, PROMPT_SMM, back_button("cat_work"))
    elif data == "prompt_resume":
        await update_interface(callback.message.chat.id, PROMPT_RESUME, back_button("cat_work"))
    elif data == "prompt_cover":
        await update_interface(callback.message.chat.id, PROMPT_COVER_LETTER, back_button("cat_work"))
    elif data == "prompt_history":
        await update_interface(callback.message.chat.id, PROMPT_GAME_HISTORY, back_button("cat_game"))

# --- ГЛОБАЛЬНЫЙ ОБРАБОТЧИК (ЛОВУШКА) ---
# Срабатывает на любой текст, который не является командой или нажатием кнопки
@dp.message()
async def any_message_handler(message: types.Message, state: FSMContext):
    await state.clear()
    await update_interface(message.chat.id, "Я готов к работе! Выбери категорию промтов ниже:", main_inline_menu())

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
    
    # Запуск бота
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
