import os
import discord # type: ignore
from discord.ext import tasks # type: ignore
import re
from models import DiscordUser, VCTracker

intents = discord.Intents.default()
client = discord.Client(intents=intents)

async def send_message(content, channel=None):
    try:
        await channel.send(content)
    except Exception as e:
        print(f"Encountered exception: {e}")

async def get_discord_id(message):
    user_tag = message.content.split("$getid ", 1)[1]
    user = await client.fetch_user(re.sub("[^0-9]", "", user_tag))
    await send_message(f"<@{user.id}> Discord ID is `{user.id}`", message.channel)

@tasks.loop(seconds=86400)
async def daily_ping():
    if os.getenv("STAGING"): #dont do this in staging
        return
    channel_id = 907489456007807009 #Channel ID of channel to post this message in
    send_message("Daily ping", channel_id)

#GENERIC STUFF
@client.event
async def on_ready():
    daily_ping.start()
    print("Bot Running")

@client.event
async def on_message(message):
    if message.content.startswith("$ping"):
        await send_message(f"Pong! In {round(client.latency * 1000)}ms", message.channel)
    
    if message.author == client.user:
        return

    if isinstance(message.channel, discord.channel.DMChannel):
        return

    if message.content.startswith("$getid"):
        await get_discord_id(message)

client.run(os.getenv('DISCORD_TOKEN'))
