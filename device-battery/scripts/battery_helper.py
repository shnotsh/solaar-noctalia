#!/usr/bin/env python3
"""One bounded provider query; JSON only on stdout, diagnostics on stderr."""
import argparse
import contextlib
import importlib
import json
import sys
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--provider', required=True, choices=['system', 'logitech', 'eightbitdo'])
    args = parser.parse_args()
    started = time.monotonic()
    result = dict(schema=1, provider=args.provider, devices=[], errors=[], ok=True)
    try:
        with contextlib.redirect_stdout(sys.stderr):
            provider = importlib.import_module('providers.' + args.provider)
            result['devices'], result['errors'] = provider.scan()
    except (Exception, SystemExit) as exc:
        result.update(ok=False, errors=[type(exc).__name__ + ': ' + str(exc)[:250]])
    result.update(sampled_at=int(time.time()), elapsed_ms=round((time.monotonic()-started)*1000))
    print(json.dumps(result, allow_nan=False))


if __name__ == '__main__':
    main()
