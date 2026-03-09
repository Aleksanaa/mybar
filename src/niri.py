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
            cls._instance._lock = None
        return cls._instance

    @property
    def lock(self):
        if self._lock is None:
            self._lock = asyncio.Lock()
        return self._lock

    async def _connect(self):
        if not self.socket_path:
            return False
        try:
            self.reader, self.writer = await asyncio.open_unix_connection(
                self.socket_path
            )
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
                self.writer.write(json.dumps(data).encode("utf-8") + b"\n")
                await self.writer.drain()

                # Wait for the response
                response_line = await self.reader.readline()
                if not response_line:
                    return {"error": "Empty response from niri socket"}

                try:
                    return json.loads(response_line.decode("utf-8"))
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

    async def stream_events(self):
        """
        Connects to the niri socket, sends an 'EventStream' request,
        and yields events as an async generator. This opens a separate
        connection to avoid blocking regular send() requests.
        """
        if not self.socket_path:
            print(
                "NIRI_SOCKET environment variable not set, cannot start event stream.",
                file=sys.stderr,
            )
            return

        while True:
            reader = None
            writer = None
            try:
                reader, writer = await asyncio.open_unix_connection(self.socket_path)

                # Send EventStream request
                writer.write(json.dumps("EventStream").encode("utf-8") + b"\n")
                await writer.drain()

                while True:
                    line = await reader.readline()
                    if not line:
                        break  # Connection closed or EOF

                    try:
                        event = json.loads(line.decode("utf-8"))
                        yield event
                    except json.JSONDecodeError as e:
                        print(
                            f"Failed to parse niri EventStream JSON: {e}",
                            file=sys.stderr,
                        )

            except Exception as e:
                print(f"Error in niri EventStream connection: {e}", file=sys.stderr)

            finally:
                if writer:
                    try:
                        writer.close()
                        await writer.wait_closed()
                    except Exception:
                        pass

            # Wait a bit before trying to reconnect if the connection dropped
            await asyncio.sleep(1)


# Shared connection instance
niri_conn = NiriConnection()
