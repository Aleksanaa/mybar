import asyncio
import sys
import json
import os

# Try to import numpy
try:
    import numpy as np

    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False

from ..utils import write_json
from ..tasks import long_running_task

# Configuration
NUM_BARS = 24
SAMPLING_RATE = 44100
FFT_SIZE = 2048
UPDATE_INTERVAL = 0.02  # ~50 FPS for smoothness


class CavaProcessor:
    def __init__(self, num_bars):
        self.num_bars = num_bars
        self.prev_bars = np.zeros(num_bars)
        self.fall_velocity = np.zeros(num_bars)
        self.dynamic_gain = 0.05
        self.gravity = 0.02

    def process(self, samples):
        if not HAS_NUMPY:
            return [0.0] * self.num_bars

        # 1. Windowing & FFT
        windowed = samples * np.hanning(len(samples))
        fft_res = np.abs(np.fft.rfft(windowed)) / (len(samples) / 2)

        # 2. Focus on audible range (50Hz - 15kHz)
        low_idx = int(50 * len(samples) / SAMPLING_RATE)
        high_idx = int(15000 * len(samples) / SAMPLING_RATE)
        data = fft_res[low_idx:high_idx]

        if len(data) == 0:
            return self.fall_off()

        # 3. Logarithmic binning with Max-pooling (more reactive than mean)
        indices = np.geomspace(1, len(data), self.num_bars + 1).astype(int) - 1
        raw_bars = np.zeros(self.num_bars)

        for i in range(self.num_bars):
            start, end = indices[i], indices[i + 1]
            if start >= end:
                raw_bars[i] = data[min(start, len(data) - 1)]
            else:
                raw_bars[i] = np.max(data[start:end])

        # 4. Slope / Weighting (boost treble slightly)
        weighting = np.linspace(1.0, 3.5, self.num_bars)
        raw_bars *= weighting

        # 5. Dynamic Gain Control (DGC)
        # This is the "magic" that keeps bars reaching the top regardless of volume
        current_max = np.max(raw_bars)
        if current_max > self.dynamic_gain:
            self.dynamic_gain = (
                self.dynamic_gain * 0.7 + current_max * 0.3
            )  # Rapid rise
        else:
            self.dynamic_gain = (
                self.dynamic_gain * 0.995 + current_max * 0.005
            )  # Very slow fall

        # Ensure we don't divide by near-zero during silence
        gain_floor = max(self.dynamic_gain, 0.005)
        normalized = np.clip(raw_bars / gain_floor, 0, 1)

        # Non-linear scaling to make low energy more visible
        normalized = np.power(normalized, 0.6)

        # 6. Gravity (Fall-off)
        for i in range(self.num_bars):
            if normalized[i] > self.prev_bars[i]:
                self.prev_bars[i] = normalized[i]
                self.fall_velocity[i] = 0
            else:
                self.fall_velocity[i] += self.gravity
                self.prev_bars[i] = max(0, self.prev_bars[i] - self.fall_velocity[i])

        return self.prev_bars.tolist()

    def fall_off(self):
        for i in range(self.num_bars):
            self.fall_velocity[i] += self.gravity
            self.prev_bars[i] = max(0, self.prev_bars[i] - self.fall_velocity[i])
        return self.prev_bars.tolist()


@long_running_task
async def audio_visualizer_monitor(writer):
    if not HAS_NUMPY:
        return

    processor = CavaProcessor(NUM_BARS)
    chunk_size = FFT_SIZE * 2

    cmd = [
        "parec",
        "--format=s16le",
        "--channels=1",
        "--rate=44100",
        "--latency-msec=10",
        "--device=@DEFAULT_SINK@.monitor",
    ]

    while True:
        proc = None
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL
            )

            while True:
                try:
                    # No artificial sleep; throttled by audio stream
                    data = await proc.stdout.readexactly(chunk_size)
                except:
                    break

                samples = (
                    np.frombuffer(data, dtype=np.int16).astype(np.float32) / 32768.0
                )
                bars = processor.process(samples)

                await write_json(writer, {"visualizer": bars})

        except asyncio.CancelledError:
            if proc:
                proc.kill()
            raise
        except Exception as e:
            print(f"Audio Visualizer error: {e}", file=sys.stderr)
            await asyncio.sleep(2)
        finally:
            if proc:
                try:
                    proc.kill()
                    await proc.wait()
                except:
                    pass
