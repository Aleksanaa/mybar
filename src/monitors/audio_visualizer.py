import asyncio
import sys
import os

# Set latency hint for PulseAudio/Pipewire before soundcard imports
os.environ["PULSE_LATENCY_MSEC"] = "20"

import soundcard as sc

# Try to import numpy
try:
    import numpy as np

    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False

from ..utils import write_json
from ..tasks import long_running_task

# Shared state to allow mpris_monitor to toggle visualizer
PLAYBACK_EVENT = asyncio.Event()
# Shared state to allow UI to toggle visualizer (e.g. only when popup is open)
VISUALIZER_ENABLED_EVENT = asyncio.Event()

# Configuration
NUM_BARS = 24
SAMPLING_RATE = 44100
FFT_SIZE = 2048  # Balanced resolution/latency


class CavaProcessor:
    def __init__(self, num_bars, sampling_rate, fft_size):
        self.num_bars = num_bars
        self.prev_bars = np.zeros(num_bars, dtype=np.float32)
        self.fall_velocity = np.zeros(num_bars, dtype=np.float32)
        self.dynamic_gain = 0.05
        self.gravity = 0.015
        self.smooth_factor = 0.6

        # Pre-compute window and audible range indices
        self.window = np.hanning(fft_size).astype(np.float32)
        self.low_idx = int(50 * fft_size / sampling_rate)
        self.high_idx = int(15000 * fft_size / sampling_rate)

        # Pre-compute binning indices
        data_len = max(1, self.high_idx - self.low_idx)
        self.indices = np.geomspace(1, data_len, num_bars + 1).astype(int) - 1

        # Pre-compute frequency weighting (boost treble)
        self.weighting = np.linspace(1.0, 3.5, num_bars).astype(np.float32)

    def process(self, samples):
        if not HAS_NUMPY:
            return [0.0] * self.num_bars

        # OPTIMIZATION: Skip FFT if the input chunk is essentially silent
        # This saves significant CPU when no audio is playing
        if np.max(np.abs(samples)) < 0.001:
            return self.fall_off()

        # 1. Windowing & FFT
        windowed = samples * self.window
        fft_res = np.abs(np.fft.rfft(windowed)) / (len(samples) / 2)

        # 2. Focus on audible range
        data = fft_res[self.low_idx : self.high_idx]
        if len(data) == 0:
            return self.fall_off()

        # 3. Logarithmic binning with Max-pooling
        raw_bars = np.zeros(self.num_bars, dtype=np.float32)
        for i in range(self.num_bars):
            start, end = self.indices[i], self.indices[i + 1]
            if start >= end:
                raw_bars[i] = data[min(start, len(data) - 1)]
            else:
                raw_bars[i] = np.max(data[start:end])

        # 4. Weighting & Dynamic Gain Control
        raw_bars *= self.weighting
        current_max = np.max(raw_bars)

        if current_max > self.dynamic_gain:
            self.dynamic_gain = self.dynamic_gain * 0.7 + current_max * 0.3
        else:
            self.dynamic_gain = self.dynamic_gain * 0.995 + current_max * 0.005

        # 5. Normalization
        gain_floor = max(self.dynamic_gain, 0.005)
        normalized = np.power(np.clip(raw_bars / gain_floor, 0, 1), 0.6)

        # 6. Temporal Smoothing & Gravity (Vectorized)
        rising = normalized > self.prev_bars
        self.prev_bars[rising] = (normalized[rising] * self.smooth_factor) + (
            self.prev_bars[rising] * (1 - self.smooth_factor)
        )
        self.fall_velocity[rising] = 0

        falling = ~rising
        self.fall_velocity[falling] += self.gravity
        self.prev_bars[falling] = np.maximum(
            0, self.prev_bars[falling] - self.fall_velocity[falling]
        )

        # OPTIMIZATION: Rounding reduces JSON size and stringification overhead
        return np.round(self.prev_bars, 2).tolist()

    def fall_off(self):
        self.fall_velocity += self.gravity
        self.prev_bars = np.maximum(0, self.prev_bars - self.fall_velocity)
        return np.round(self.prev_bars, 2).tolist()


@long_running_task
async def audio_visualizer_monitor(writer):
    if not HAS_NUMPY:
        return

    processor = CavaProcessor(NUM_BARS, SAMPLING_RATE, FFT_SIZE)
    chunk_duration = FFT_SIZE / SAMPLING_RATE

    while True:
        try:
            # Wait until both something starts playing AND the visualizer is enabled by the UI
            while not (PLAYBACK_EVENT.is_set() and VISUALIZER_ENABLED_EVENT.is_set()):
                tasks = []
                if not PLAYBACK_EVENT.is_set():
                    tasks.append(asyncio.create_task(PLAYBACK_EVENT.wait()))
                if not VISUALIZER_ENABLED_EVENT.is_set():
                    tasks.append(asyncio.create_task(VISUALIZER_ENABLED_EVENT.wait()))

                if tasks:
                    await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
                    for t in tasks:
                        if not t.done():
                            t.cancel()

            speaker = sc.default_speaker()
            mic = sc.get_microphone(speaker.id + ".monitor", include_loopback=True)

            last_was_zero = False
            # Counter for how long it's been silent to decide when to stop recording
            silence_counter = 0

            with mic.recorder(samplerate=SAMPLING_RATE, channels=1) as recorder:
                while (
                    PLAYBACK_EVENT.is_set()
                    and VISUALIZER_ENABLED_EVENT.is_set()
                    or silence_counter < 50
                ):  # ~1s grace period
                    t0 = asyncio.get_event_loop().time()
                    data = await asyncio.to_thread(recorder.record, numframes=FFT_SIZE)
                    t1 = asyncio.get_event_loop().time()

                    # Drain buffer if lagging
                    while (t1 - t0) < chunk_duration * 0.8:
                        t0 = t1
                        data = await asyncio.to_thread(
                            recorder.record, numframes=FFT_SIZE
                        )
                        t1 = asyncio.get_event_loop().time()

                    samples = data.flatten().astype(np.float32)
                    bars = processor.process(samples)

                    is_zero = np.all(processor.prev_bars < 0.01)
                    if is_zero:
                        silence_counter += 1
                    else:
                        silence_counter = 0

                    if not (is_zero and last_was_zero):
                        await write_json(writer, {"visualizer": bars})
                    last_was_zero = is_zero

                    # If MPRIS says it stopped OR visualizer was disabled, we don't need to record anymore
                    if (
                        not (
                            PLAYBACK_EVENT.is_set()
                            and VISUALIZER_ENABLED_EVENT.is_set()
                        )
                        and is_zero
                    ):
                        break

        except asyncio.CancelledError:
            raise
        except Exception as e:
            print(f"Audio Visualizer error: {e}", file=sys.stderr)
            await asyncio.sleep(2)
