import asyncio
import json
import os
import sys


class NiriConnection:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(NiriConnection, cls).__new__(cls)
            cls._instance.socket_path = os.environ.get("NIRI_SOCKET")
            cls._instance.reader = None
            cls._instance.writer = None
            cls._instance.lock = asyncio.Lock()
        return cls._instance

    async def _connect(self):
        if not self.socket_path:
            return False
        try:
            self.reader, self.writer = await asyncio.open_unix_connection(self.socket_path)
            return True
        except Exception as e:
            print(f"Error connecting to niri socket: {e}", file=sys.stderr)
            return False

    async def send(self, data):
        """
        Sends a Python object as JSON to the niri socket and returns the parsed JSON response.
        """
        if not self.socket_path:
            return {"error": "NIRI_SOCKET environment variable not set"}

        async with self.lock:
            if self.writer is None:
                if not await self._connect():
                    return {"error": "Could not connect to niri socket"}

            try:
                # Send request and append a newline
                self.writer.write(json.dumps(data).encode('utf-8') + b'\n')
                await self.writer.drain()

                # Wait for the response
                response_line = await self.reader.readline()
                if not response_line:
                    return {"error": "Empty response from niri socket"}
                
                try:
                    return json.loads(response_line.decode('utf-8'))
                except json.JSONDecodeError as e:
                    return {"error": f"Failed to parse JSON response: {e}"}

            except Exception as e:
                # Invalidate connection on error
                if self.writer:
                    try:
                        self.writer.close()
                        await self.writer.wait_closed()
                    except Exception:
                        pass
                self.writer = None
                self.reader = None
                print(f"Error communicating with niri socket: {e}", file=sys.stderr)
                return {"error": str(e)}
        return None
