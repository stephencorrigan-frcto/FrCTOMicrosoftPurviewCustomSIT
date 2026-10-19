import asyncio
import aiohttp

async def fetch(session, url):
    async with session.get(url) as resp:
        return await resp.json()

async def main():
    async with aiohttp.ClientSession() as session:
        data = await fetch(session, "https://example.com/api")
        print(data)

asyncio.run(main())