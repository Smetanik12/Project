import asyncio
import logging
import os
import sys

# Настройка логирования, чтобы видеть ошибки в консоли Render
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

try:
    from prompts import PROMPT_EGE, PROMPT_ITOG, PROMPT_SPORT, PROMPT_COOKING
    logger.info("Промты успешно импортированы!")
except Exception as e:
    logger.error(f"ОШИБКА ИМПОРТА: {e}")
    sys.exit(1) # Завершаем работу, если промты не загрузились

# ... дальше твой остальной код бота ...
