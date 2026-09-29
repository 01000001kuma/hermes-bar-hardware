# Hermes Hardware — Omarchy bar hardware widget

A Quickshell bar widget for Omarchy: a compact `CPU  RAM  peak-temp` badge with a
drill-down panel that decomposes **every** number it shows — per-core sparklines,
named temperature sensors, every discovered GPU, every real disk mount.

Written for [Omarchy](https://omarchy.org/) / [Quickshell](https://quickshell.outfoxxed.me/).

## Why this one

Most hardware widgets show one number per resource and stop there. This one is built
around a simple contract:

> **Every number in the badge decomposes into the panel, and the panel's numbers are
> exactly the badge's numbers.** One arithmetic, two levels of zoom.

It also refuses to fake data. A machine with no temperature sensors, an iGPU without
usable counters, or a stale sampler reads as `--` or "no counter" — **never** as a
silent `0%` (the failure most widgets make).

## Install

```sh
omarchy plugin add https://github.com/01000001kuma/hermes-bar-hardware --enable
```

Then add `hermes.hardware` to your bar layout (Settings → bar layout, or
`omarchy bar move hermes.hardware --section right`).

## What it shows

**Badge** — `14%  47%  69°C` (CPU mean, RAM, peak temperature). Each part the machine
cannot report is simply omitted.

**Panel (click)** — every badge number, decomposed:

| Badge number | Panel decomposition |
|---|---|
| CPU mean % | one sparkline + % per core (core count discovered from `/proc/stat`) |
| RAM % | used/total GiB, swap usage (or "none") |
| Peak temp °C | every sensor with its chip label (`k10temp · Tdie`, `coretemp · Package id 0`, …) |
| GPU % (tooltip) | each GPU: usage, VRAM used/total, temperature — or "no counter" |

**Foot** — load averages and uptime.

## Nothing hardcoded

All discovery is at runtime, per machine:

- **CPU cores** — parsed from `/proc/stat` (works with any core count)
- **Temperatures** — `lm-sensors` (`sensors -j`) with its human labels; falls back to
  `/sys/class/thermal`
- **GPUs** — `/sys/class/drm/card*/device/vendor` (`0x1002` AMD, `0x8086` Intel,
  `0x10de` NVIDIA), with names from `lspci` when available; VRAM from the standard
  sysfs counters
- **Disks** — every real mount (filtered pseudo-filesystems) of at least
  `minDiskGiB` (configurable)

No hardcoded device names, no `home/akuma` paths, no assumptions about hardware
layout. On a two-GPU desktop, a single-kernel laptop, or a 32-core workstation, it
adapts.

## Configuration (bar-widget schema)

| Key | Default | Meaning |
|---|---|---|
| `intervalSec` | 3 | seconds between samples |
| `diskWarnPercent` | 80 | disk bar turns amber past this |
| `diskCritPercent` | 90 | disk bar turns red past this |
| `tempWarnC` | 80 | sensor list turns red past this |
| `minDiskGiB` | 1 | hide mounts smaller than this |

## Requirements

- Omarchy (Quickshell shell) 0.7.x
- `python3` for the sampler (stdlib only — zero dependencies)
- optional: `lm_sensors` for named sensors, `pciutils` for GPU names

## License

MIT — same as Omarchy itself.