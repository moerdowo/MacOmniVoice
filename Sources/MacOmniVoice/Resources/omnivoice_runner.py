"""JSON-line bridge that loads OmniVoice once and serves synthesis requests.

Protocol:
  Input  (stdin, one JSON object per line):
    {"action": "ping"}
    {"action": "load", "model_id": "k2-fsa/OmniVoice"}
    {"action": "synthesize", "params": {...}, "out_path": "/tmp/x.wav"}
    {"action": "model_info", "model_id": "k2-fsa/OmniVoice"}
    {"action": "quit"}

  Output (stdout, one JSON object per line):
    {"event": "pong"}
    {"event": "load_start", ...}
    {"event": "load_done", "sampling_rate": 24000, "device": "mps"}
    {"event": "synthesize_start"}
    {"event": "synthesize_done", "out_path": "/tmp/x.wav", "duration": 3.4}
    {"event": "model_info", "snapshot_dir": "...", "revision": "..."}
    {"event": "error", "msg": "...", "traceback": "..."}
    {"event": "log", "level": "info", "msg": "..."}
"""

from __future__ import annotations

import inspect
import json
import os
import sys
import time
import traceback
from pathlib import Path
from typing import Any

# Make sure stdout is line-buffered so the Swift host sees events promptly.
try:
    sys.stdout.reconfigure(line_buffering=True)  # type: ignore[attr-defined]
except Exception:
    pass


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def log(level: str, msg: str) -> None:
    emit({"event": "log", "level": level, "msg": msg})


# --- HuggingFace download progress -----------------------------------------

def _make_progress_tqdm():
    """Return a custom tqdm class that emits JSON progress events."""
    try:
        from tqdm.auto import tqdm as _tqdm
    except Exception:
        return None

    class JSONTqdm(_tqdm):  # type: ignore[misc]
        def __init__(self, *a, **kw):
            super().__init__(*a, **kw)
            self._last_emit = 0
            self._emit("start")

        def update(self, n=1):
            super().update(n)
            now = time.time()
            # Throttle to ~5 events per second per bar.
            if now - self._last_emit > 0.2 or (self.total and self.n >= self.total):
                self._emit("update")
                self._last_emit = now

        def close(self):
            try:
                self._emit("close")
            finally:
                super().close()

        def _emit(self, kind):
            try:
                emit({
                    "event": "download_progress",
                    "phase": kind,
                    "desc": str(self.desc or ""),
                    "unit": str(self.unit or ""),
                    "n": int(self.n or 0),
                    "total": int(self.total or 0) if self.total else 0,
                })
            except Exception:
                pass

    return JSONTqdm


def _hf_repo_cache_dir(model_id: str):
    """Path to the per-repo cache dir, e.g.
    ~/.cache/huggingface/hub/models--k2-fsa--OmniVoice — without importing
    the constants module (which has differed across hub versions)."""
    from pathlib import Path
    try:
        from huggingface_hub import constants  # type: ignore
        base = Path(constants.HF_HUB_CACHE)
    except Exception:
        base = Path.home() / ".cache/huggingface/hub"
    return base / ("models--" + model_id.replace("/", "--"))


def _measure_cached_bytes(repo_dir) -> tuple[int, int]:
    """Return (downloaded_bytes, in_flight_bytes) inside the repo cache.

    `downloaded_bytes` counts finalised blobs; `in_flight_bytes` counts
    `*.incomplete` shards currently being written. Together they're the
    real number to display.
    """
    if not repo_dir.exists():
        return (0, 0)
    blobs = repo_dir / "blobs"
    if not blobs.exists():
        return (0, 0)
    done = 0
    pending = 0
    try:
        for p in blobs.iterdir():
            try:
                sz = p.stat().st_size
            except OSError:
                continue
            if p.name.endswith(".incomplete"):
                pending += sz
            else:
                done += sz
    except OSError:
        pass
    return (done, pending)


def _ensure_model_downloaded(model_id: str) -> str:
    """Use huggingface_hub.snapshot_download for the real download, and
    a background polling thread to emit accurate progress events based
    on the on-disk byte count of the per-repo cache directory."""
    import threading
    from huggingface_hub import snapshot_download  # type: ignore

    emit({"event": "download_start", "model_id": model_id})

    repo_dir = _hf_repo_cache_dir(model_id)
    # Establish a baseline so we report new bytes since the user clicked
    # download (otherwise existing partial bytes look like instant progress).
    base_done, base_pending = _measure_cached_bytes(repo_dir)
    base_total = base_done + base_pending

    stop = threading.Event()

    def poll():
        while not stop.is_set():
            done, pending = _measure_cached_bytes(repo_dir)
            emit({
                "event": "download_progress",
                "phase": "poll",
                "desc": "Downloading model from HuggingFace",
                "unit": "B",
                "n": int(done + pending),
                "total": 0,            # total is filled in by Swift via /tree
                "baseline": int(base_total),
            })
            stop.wait(1.0)

    t = threading.Thread(target=poll, daemon=True)
    t.start()

    try:
        path = snapshot_download(repo_id=model_id)
    finally:
        stop.set()
        t.join(timeout=2.0)

    # Final tick so the UI lands on the true post-download value.
    done, pending = _measure_cached_bytes(repo_dir)
    emit({
        "event": "download_progress",
        "phase": "final",
        "desc": "Download complete",
        "unit": "B",
        "n": int(done + pending),
        "total": int(done + pending),
        "baseline": int(base_total),
    })

    emit({"event": "download_done", "model_id": model_id, "snapshot_path": str(path)})
    return path


_model = None
_sampling_rate: int | None = None
_device: str | None = None


def _get_best_device() -> str:
    try:
        from omnivoice.utils.common import get_best_device  # type: ignore
        return get_best_device()
    except Exception:
        pass
    try:
        import torch
        if torch.backends.mps.is_available():
            return "mps"
        if torch.cuda.is_available():
            return "cuda:0"
    except Exception:
        pass
    return "cpu"


def load_model(model_id: str, device_override: str | None = None) -> None:
    global _model, _sampling_rate, _device

    import torch
    from omnivoice.models.omnivoice import OmniVoice  # type: ignore

    device = device_override or _get_best_device()
    emit({"event": "load_start", "model_id": model_id, "device": device})

    # Pre-download with explicit progress so the UI isn't left wondering
    # whether the (potentially multi-GB) HF weights are stuck.
    try:
        _ensure_model_downloaded(model_id)
    except Exception as e:
        log("warn", f"snapshot_download failed ({e}); falling back to from_pretrained.")

    # MPS prefers float16; CPU prefers float32 for stability.
    dtype = torch.float16 if device != "cpu" else torch.float32
    try:
        _model = OmniVoice.from_pretrained(model_id, device_map=device, dtype=dtype)
    except Exception as e:
        # Retry on CPU with float32 if the requested device failed.
        if device != "cpu":
            log("warn", f"Loading on {device} failed ({e}); retrying on cpu/float32.")
            device = "cpu"
            dtype = torch.float32
            _model = OmniVoice.from_pretrained(model_id, device_map=device, dtype=dtype)
        else:
            raise

    _device = device
    _sampling_rate = int(getattr(_model, "sampling_rate", 24000))
    emit({"event": "load_done", "sampling_rate": _sampling_rate, "device": device})


def synthesize(params: dict, out_path: str) -> None:
    if _model is None:
        raise RuntimeError("Model is not loaded yet. Send 'load' first.")

    import soundfile as sf  # type: ignore

    sig = inspect.signature(_model.generate)  # type: ignore[attr-defined]
    accepted = set(sig.parameters.keys())

    kwargs: dict[str, Any] = {}
    for k, v in params.items():
        if v is None:
            continue
        if isinstance(v, str) and v.strip() == "":
            continue
        if k in accepted:
            kwargs[k] = v

    # Always require text.
    if "text" not in kwargs:
        raise ValueError("Missing required 'text' parameter.")

    emit({"event": "synthesize_start", "accepted": sorted(kwargs.keys())})
    started = time.time()
    audios = _model.generate(**kwargs)  # type: ignore[attr-defined]
    elapsed = time.time() - started

    out = Path(out_path).expanduser()
    out.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(out), audios[0], _sampling_rate or 24000)
    emit({
        "event": "synthesize_done",
        "out_path": str(out),
        "elapsed": round(elapsed, 3),
    })


def model_info(model_id: str) -> None:
    """Return information about the locally cached snapshot, if any."""
    info: dict[str, Any] = {"event": "model_info", "model_id": model_id}
    try:
        from huggingface_hub import constants  # type: ignore
        try:
            from huggingface_hub import scan_cache_dir  # type: ignore
        except Exception:
            scan_cache_dir = None

        info["cache_dir"] = str(constants.HF_HUB_CACHE)

        if scan_cache_dir is not None:
            cache = scan_cache_dir()
            for repo in cache.repos:
                if repo.repo_id == model_id and repo.repo_type == "model":
                    info["size_on_disk"] = int(repo.size_on_disk)
                    info["nb_files"] = int(repo.nb_files)
                    revs = []
                    for rev in repo.revisions:
                        revs.append({
                            "commit_hash": rev.commit_hash,
                            "snapshot_path": str(rev.snapshot_path),
                            "size_on_disk": int(rev.size_on_disk),
                            "refs": sorted(list(rev.refs)) if rev.refs else [],
                        })
                    info["revisions"] = revs
                    break
    except Exception as e:
        info["scan_error"] = str(e)
    emit(info)


def download_model(model_id: str) -> None:
    """Force download / refresh the model snapshot via huggingface_hub."""
    _ensure_model_downloaded(model_id)


def main() -> None:
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                req = json.loads(line)
            except json.JSONDecodeError as e:
                emit({"event": "error", "msg": f"invalid json: {e}"})
                continue

            action = req.get("action")
            try:
                if action == "ping":
                    emit({"event": "pong"})
                elif action == "load":
                    load_model(
                        req["model_id"],
                        device_override=req.get("device"),
                    )
                elif action == "synthesize":
                    synthesize(req["params"], req["out_path"])
                elif action == "model_info":
                    model_info(req["model_id"])
                elif action == "download":
                    download_model(req["model_id"])
                elif action == "quit":
                    emit({"event": "bye"})
                    return
                else:
                    emit({"event": "error", "msg": f"unknown action: {action}"})
            except Exception as e:
                emit({
                    "event": "error",
                    "msg": str(e),
                    "traceback": traceback.format_exc(),
                    "action": action,
                })
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
