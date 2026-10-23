import contextlib
import math
import signal
import time


def percentage(value):
    try:
        n = float(value)
        return round(n) if math.isfinite(n) and 0 <= n <= 100 else None
    except (TypeError, ValueError):
        return None


def record(identity, name, kind, provider, percent=None, **extra):
    return dict(id=identity, name=str(name), kind=kind, provider=provider,
                percent=percentage(percent), state="unknown", online=True,
                observed_at=int(time.time()), precision="percent", **extra)


def read(path, default=""):
    try:
        return path.read_text().strip()
    except OSError:
        return default


@contextlib.contextmanager
def deadline(seconds):
    def expired(*_):
        raise TimeoutError("Device query timed out")
    previous = signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)
