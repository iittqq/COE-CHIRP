import asyncio
import websockets
import json

connected_clients = set()


async def handler(websocket):
    print("Client connected")
    connected_clients.add(websocket)

    try:
        async for message in websocket:
            print("Received:", message)
            try:
                data = json.loads(message)
                print("Parsed command:", data)

                to_remove = set()
                for client in connected_clients:
                    if client != websocket:
                        try:
                            await client.send(message)
                        except websockets.exceptions.ConnectionClosed:
                            to_remove.add(client)

                connected_clients.difference_update(to_remove)

            except json.JSONDecodeError:
                print("Invalid JSON received")
    except websockets.exceptions.ConnectionClosed:
        print("Client disconnected")
    finally:
        connected_clients.discard(websocket)


async def main():
    async with websockets.serve(handler, "0.0.0.0", 8080):
        print("WebSocket server running on ws://0.0.0.0:8080")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
