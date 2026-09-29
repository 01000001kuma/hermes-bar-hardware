#!/usr/bin/env python3
"""Smoke tests for the hardware-stats sampler output contract."""
import json
import subprocess
import sys
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLER = os.path.join(HERE, "..", "bin", "hardware-stats")

def main():
    raw = subprocess.check_output([SAMPLER], text=True, timeout=30)
    doc = json.loads(raw)
    failures = []

    if doc.get("schema") != 1:
        failures.append("schema must be 1")
    if not isinstance(doc.get("cpu", {}).get("coresPercent"), list) or not doc["cpu"]["coresPercent"]:
        failures.append("cpu.coresPercent must be a non-empty list")
    mean = doc["cpu"].get("meanPercent")
    if mean is not None and not isinstance(mean, (int, float)):
        failures.append("cpu.meanPercent must be number or null")
    mem = doc.get("memory", {})
    for key in ("percent", "usedGiB", "totalGiB", "swapPercent", "swapUsedGiB", "swapTotalGiB"):
        if key not in mem:
            failures.append(f"memory.{key} missing")
    for sensor in doc.get("sensors", []):
        if "label" not in sensor or "celsius" not in sensor:
            failures.append("sensor entries need label+celsius")
    for gpu in doc.get("gpus", []):
        if "type" not in gpu:
            failures.append("gpu entries need type")
        # nulls are legal; zeros fake-data are not for a GPU with no counter
    if not isinstance(doc.get("disks"), list):
        failures.append("disks missing")
    for disk in doc.get("disks", []):
        for key in ("mount", "percent", "usedGiB", "totalGiB"):
            if key not in disk:
                failures.append(f"disk entry missing {key}")
    if len(doc.get("load", [])) != 3:
        failures.append("load must have 3 values")

    if failures:
        for f in failures:
            print("FAIL:", f)
        sys.exit(1)
    print("OK — sampler output contract holds:",
          len(doc["cpu"]["coresPercent"]), "cores,",
          len(doc["sensors"]), "sensors,",
          len(doc["gpus"]), "gpus,",
          len(doc["disks"]), "disks")

if __name__ == "__main__":
    main()
