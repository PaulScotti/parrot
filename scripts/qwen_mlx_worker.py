#!/usr/bin/env python3
"""Persistent JSON-lines worker for Qwen3-ASR inference through MLX Audio."""

from __future__ import annotations

import argparse
import contextlib
import json
import sys
import traceback


def emit(message: dict[str, object]) -> None:
    sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    try:
        with contextlib.redirect_stdout(sys.stderr):
            from mlx_audio.stt import load

            model = load(args.model)
        emit({"type": "ready", "model": args.model})
    except Exception as error:
        traceback.print_exc(file=sys.stderr)
        emit({"type": "error", "error": str(error)})
        return 1

    if args.check:
        return 0

    for line in sys.stdin:
        request_id = None
        try:
            request = json.loads(line)
            request_id = request.get("id")
            if request.get("type") != "transcribe":
                raise ValueError("unknown request type")
            with contextlib.redirect_stdout(sys.stderr):
                result = model.generate(
                    request["audio"],
                    language=request.get("language", "English"),
                    temperature=0.0,
                    verbose=False,
                )
            emit({"type": "result", "id": request_id, "text": result.text.strip()})
        except Exception as error:
            traceback.print_exc(file=sys.stderr)
            emit({"type": "error", "id": request_id, "error": str(error)})

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
