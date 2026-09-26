#!/usr/bin/env python3
"""Turn an .ips crash report into a readable stack.

The report carries offsets into each image and, in usedImages, the address each
image was loaded at. atos does the rest -- as long as it gets the very binary
that crashed, which in CI is right there next to the report.

    tools/symbolicate.py <bericht.ips> <pyrogenesis>
"""
import json
import subprocess
import sys


def main(report_path: str, binary: str) -> int:
    raw = open(report_path, encoding="utf-8", errors="replace").read()
    _, body = raw.split("\n", 1)
    report = json.loads(body)

    print("Grund     :", report.get("exception", {}).get("type"),
          report.get("exception", {}).get("subtype", ""))
    print("Signal    :", report.get("termination", {}).get("indicator"))

    # Which pointer was null: the registers say it outright.
    state = report.get("threads", [{}])[report.get("faultingThread", 0)].get("threadState", {})
    if state:
        registers = state.get("x", [])
        print("Register  :", ", ".join(
            "x%d=0x%x" % (number, entry.get("value", 0))
            for number, entry in enumerate(registers[:8])))
        for name in ("pc", "lr", "sp", "fp"):
            if name in state:
                print("%-10s: 0x%x" % (name, state[name].get("value", 0)))

    images = report.get("usedImages", [])
    threads = report.get("threads", [])
    faulting = report.get("faultingThread", 0)

    for number, thread in enumerate(threads):
        if number != faulting and not thread.get("triggered"):
            continue
        print("\nThread %d%s:" % (number, " (abgestuerzt)" if number == faulting else ""))
        for frame in thread.get("frames", []):
            index = frame.get("imageIndex", -1)
            image = images[index] if 0 <= index < len(images) else {}
            name = image.get("name", "?")
            offset = frame.get("imageOffset", 0)
            line = "  %-20s +0x%x" % (name, offset)
            if frame.get("symbol"):
                line += "   " + frame["symbol"]
            if name == "pyrogenesis":
                # atos needs the address as it was at runtime, and the address
                # the image was loaded at -- both come from the report. Passing
                # a made-up load address of 0 only gets the input back.
                base = image.get("base")
                if base is not None:
                    try:
                        resolved = subprocess.run(
                            ["atos", "-o", binary, "-arch", "arm64",
                             "-l", hex(base), hex(base + offset)],
                            capture_output=True, text=True, timeout=60).stdout.strip()
                        if resolved and not resolved.startswith("0x"):
                            line += "   " + resolved
                    except Exception as error:  # noqa: BLE001 - diagnostics only
                        line += "   (atos: %s)" % error
            print(line)
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1], sys.argv[2]))
