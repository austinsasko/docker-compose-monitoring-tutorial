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

@tasks.loop(seconds=3600)
async def daily_ping():
    channel_id = 907489456007807009 #Channel ID of channel to post this message in
    channel = client.get_channel(id=channel_id)
    if os.getenv("STAGING"): #Can do something diff in a staging environment. Use a diff channel ID, message, etc.
        await send_message("Hourly staging ping", channel)
        print("Do something different in staging")
        return
    await send_message("Hourly ping", channel)

#GENERIC STUFF
@client.event
async def on_ready():
    daily_ping.start()
    print("Bot Running")

@client.event
async def on_message(message):
    if message.content.startswith("$ping"): # If someoen sends $ping, return how long it took to process
        await send_message(f"Pong! In {round(client.latency * 1000)}ms", message.channel)
    
    if message.author == client.user: # If the bot somehow messages itself, dont do anything
        return

    if isinstance(message.channel, discord.channel.DMChannel): # If the bot is DM'd, do nothing
        return

    if message.content.startswith("$getid"): # If someone sends $getid @Austin or $getid name, return the tagged persons discord ID
        await get_discord_id(message)

client.run(os.getenv('DISCORD_TOKEN'))
