import json

async def write_json(writer, data):
    """Asynchronously write a JSON object to a stream writer."""
    writer.write(json.dumps(data).encode('utf-8') + b'\n')
    await writer.drain()

def _format_speed(speed_bps):
    """Formats speed in bytes per second to a human-readable string with specific length constraints."""
    if speed_bps == 0:
        return "0.00", "B/s"

    value = speed_bps
    unit = "B/s"

    # Scale the value to appropriate units
    if value >= 1_000_000_000:
        value /= 1_000_000_000
        unit = "GB/s"
    elif value >= 1_000_000:
        value /= 1_000_000
        unit = "MB/s"
    elif value >= 1000:
        value /= 1000
        unit = "KB/s"

    # Apply specific formatting rules
    if value >= 100:
        formatted_value = f"{value:.0f}." # e.g., "123."
    elif value >= 10:
        formatted_value = f"{value:.1f}" # e.g., "12.3"
    elif value >= 1:
        formatted_value = f"{value:.2f}" # e.g., "1.23"
    else: # value < 1
        formatted_value = f"{value:.2f}" # e.g., "0.12"
    
    return formatted_value, unit
