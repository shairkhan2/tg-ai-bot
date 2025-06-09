#!/bin/bash

echo "============================="
echo "🤖 AI Telegram Bot Installer"
echo "============================="

read -p "Enter your Gemini API Key: " GEMINI_API_KEY
read -p "Enter your DeepSeek API Key: " DEEPSEEK_API_KEY
read -p "Enter your OpenAI API Key: " OPENAI_API_KEY
read -p "Choose your OpenAI GPT model (e.g., gpt-3.5-turbo or gpt-4-turbo): " GPT_MODEL
read -p "Enter your Telegram Bot Token: " TELEGRAM_BOT_TOKEN

echo "Creating .env file..."
cat <<EOL > .env
GEMINI_API_KEY=${GEMINI_API_KEY}
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}
OPENAI_API_KEY=${OPENAI_API_KEY}
GPT_MODEL=${GPT_MODEL}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
EOL

echo "Installing dependencies..."
pip install python-telegram-bot openai google-generativeai requests python-dotenv

echo "Creating bot script (ai_bot.py)..."
cat <<'EOF' > ai_bot.py
import os
import logging
import base64
import requests
import google.generativeai as genai
from openai import OpenAI
from dotenv import load_dotenv
from telegram import Update, InputFile
from telegram.ext import ApplicationBuilder, CommandHandler, ContextTypes

load_dotenv()

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
GPT_MODEL = os.getenv("GPT_MODEL")
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")

openai_client = OpenAI(api_key=OPENAI_API_KEY)
genai.configure(api_key=GEMINI_API_KEY)

logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO)

async def askgpt(update: Update, context: ContextTypes.DEFAULT_TYPE):
    msg = update.message
    prompt = msg.caption if msg.caption else " ".join(context.args)

    if msg.forward_from or msg.forward_from_chat:
        prompt = msg.caption or msg.text or "Analyze this forwarded content."

    if not prompt:
        await msg.reply_text("❗Usage: Send /askgpt <question> or image with caption.")
        return

    try:
        if msg.photo:
            # Use GPT-4 Vision for image messages
            file = await msg.photo[-1].get_file()
            path = "temp.jpg"
            await file.download_to_drive(path)

            with open(path, "rb") as f:
                img_b64 = base64.b64encode(f.read()).decode()

            res = openai_client.chat.completions.create(
                model="gpt-4-vision-preview",
                messages=[
                    {"role": "user", "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{img_b64}"
                            }
                        }
                    ]}
                ],
                max_tokens=1000
            )
            os.remove(path)
            reply = res.choices[0].message.content
        else:
            # Use default GPT model for text
            res = openai_client.chat.completions.create(
                model=GPT_MODEL,
                messages=[{"role": "user", "content": prompt}]
            )
            reply = res.choices[0].message.content

    except Exception as e:
        reply = f"⚠️ Error: {str(e)}"

    await msg.reply_text(reply)

async def askgemini(update: Update, context: ContextTypes.DEFAULT_TYPE):
    prompt = " ".join(context.args)
    if not prompt:
        await update.message.reply_text("Usage: /askgemini <your question>")
        return
    try:
        model = genai.GenerativeModel("gemini-pro")
        res = model.generate_content(prompt)
        reply = res.text
    except Exception as e:
        reply = f"Error: {e}"
    await update.message.reply_text(reply)

async def askdeep(update: Update, context: ContextTypes.DEFAULT_TYPE):
    prompt = " ".join(context.args)
    if not prompt:
        await update.message.reply_text("Usage: /askdeep <your question>")
        return
    try:
        headers = {
            "Authorization": f"Bearer {DEEPSEEK_API_KEY}",
            "Content-Type": "application/json"
        }
        data = {
            "model": "deepseek-reasoner",
            "messages": [{"role": "user", "content": prompt}]
        }
        res = requests.post("https://api.deepseek.com/v1/chat/completions", json=data, headers=headers)
        reply = res.json()["choices"][0]["message"]["content"]
    except Exception as e:
        reply = f"Error: {e}"
    await update.message.reply_text(reply)

async def main():
    app = ApplicationBuilder().token(TELEGRAM_BOT_TOKEN).build()
    app.add_handler(CommandHandler("askgpt", askgpt))
    app.add_handler(CommandHandler("askgemini", askgemini))
    app.add_handler(CommandHandler("askdeep", askdeep))
    print("✅ Bot is running... Ctrl+C to stop.")
    await app.run_polling()

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
EOF

echo "🎉 Setup complete. Starting the bot now..."
python3 ai_bot.py
