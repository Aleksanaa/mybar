import json


async def write_json(writer, data):
    """Asynchronously write a JSON object to a stream writer."""
    writer.write(json.dumps(data).encode("utf-8") + b"\n")
    await writer.drain()
