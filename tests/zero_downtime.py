"""Sends ~10 requests/second to the app and fails if any request does not return 200.

Start it, trigger a rollout, then stop it with Ctrl+C (or pass a duration in seconds
and it stops by itself). Prints every time the version or pod seen by the client
changes, and a summary at the end. Exit code 1 if any request failed.
Run from the repo root: python tests/zero_downtime.py [url] [seconds]
"""
import re
import sys
import time
import urllib.request

# 127.0.0.1, not localhost: on Windows "localhost" tries IPv6 first, which kind does not publish, and hangs.
url = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8088/"
deadline = time.time() + float(sys.argv[2]) if len(sys.argv) > 2 else None
total, failed, seen = 0, 0, set()

try:
    while deadline is None or time.time() < deadline:
        total += 1
        try:
            body = urllib.request.urlopen(url, timeout=2).read().decode()
            version = re.search(r"Version: <b>(.*?)</b>", body).group(1)
            pod = re.search(r"pod: <b>(.*?)</b>", body).group(1)
            if (version, pod) not in seen:
                seen.add((version, pod))
                print(f"{time.strftime('%H:%M:%S')} request {total}: version={version} pod={pod}")
        except Exception as e:  # any non-200, timeout or reset counts as a failure
            failed += 1
            print(f"{time.strftime('%H:%M:%S')} request {total} FAILED: {e}")
        time.sleep(0.1)
except KeyboardInterrupt:
    pass

print(f"\n{total} requests, {failed} failed")
sys.exit(1 if failed else 0)
