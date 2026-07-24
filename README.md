# TinySpectrum

<p align="center">
  <strong>A modern macOS spectrum scanner for tinySA Ultra and Ultra+.</strong><br>
  Scan, compare, monitor, and export RF activity without sending your measurements to the cloud.
</p>

<p align="center">
  <a href="https://github.com/iron-LAN/TinySpectrum/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/iron-LAN/TinySpectrum?style=for-the-badge&color=7c3aed"></a>
  <a href="https://github.com/iron-LAN/TinySpectrum/releases/latest"><img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-0ea5e9?style=for-the-badge&logo=apple&logoColor=white"></a>
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-f97316?style=for-the-badge&logo=swift&logoColor=white">
</p>

TinySpectrum turns a tinySA Ultra into a focused desktop scanning tool. It connects automatically over USB, keeps scan history locally, supports continuous timeline capture, and exports measurements for Shure Wireless Workbench.

## Highlights

- **Automatic tinySA discovery** — connect by USB and TinySpectrum finds the serial device for you.
- **Single and continuous scanning** — capture one sweep or build a time-based RF survey.
- **Adaptive scan intervals** — choose 10 seconds, 30 seconds, 1 minute, 5 minutes, 10 minutes, or 30 minutes.
- **Resolution-aware timing** — interval and RBW selections adjust each other using the selected frequency span and estimated sweep duration.
- **Timeline playback** — move through every capture in a continuous session and inspect when activity appeared.
- **Cumulative Peak Hold** — a red overlay retains the strongest measurement at every frequency and grows as new peaks arrive.
- **Visible scan countdown** — a circular timer shows when the next continuous capture will begin.
- **Multiple scan overlays** — compare saved scans using distinct trace colors.
- **Reusable presets** — save frequently scanned frequency ranges for one-click recall.
- **Wireless Workbench export** — export regular scans as WWB-compatible CSV and continuous sessions as `.sdb3` timeline data with one antenna curve.
- **Private by design** — scans and presets remain on the Mac; approximate location is used only for optional city-based export filenames.
- **Built-in updates** — Sparkle checks the signed public update feed and can install new TinySpectrum releases from inside the app.
- **Light and dark appearance** — switch themes without leaving the scanner.

## Continuous RF surveys

Choose a frequency range, resolution, and interval, then select **Continuous**. TinySpectrum performs repeated sweeps, adds each capture to the timeline, and shows a countdown between scans.

Resolution and interval are linked:

- Choosing an **interval** selects the finest RBW expected to fit that scan cadence.
- Choosing a **resolution** selects the shortest available interval expected to accommodate the sweep.
- Changing the **frequency span** recalculates the estimate automatically.

Narrower RBW settings provide more frequency detail but can take considerably longer over a wide span. The displayed sweep time is an estimate; actual timing depends on tinySA firmware, mode, and scan conditions.

## Peak Hold

Enable **Peak Hold** above the spectrum graph during a continuous scan. The current sweep remains visible while a red line combines the strongest values observed so far.

Peak Hold is cumulative during live scanning and timeline playback: lower readings never reduce the stored peak, while later higher readings update only the affected frequencies.

## Wireless Workbench export

The **WWB** button adapts to the selected scan type:

| Scan type | Export | Contents |
| --- | --- | --- |
| Single scan | `.csv` | Frequency in MHz and amplitude in dBm |
| Continuous scan | `.sdb3` | Shure timeline container with timestamps and one antenna curve |

Continuous exports preserve the captured timeline so it can be played inside Wireless Workbench. Export filenames include the matching preset, resolution, approximate city when available, and timeline label.

## Install

1. Download the newest `TinySpectrum-v…-macOS.zip` from [Releases](https://github.com/iron-LAN/TinySpectrum/releases/latest).
2. Extract `TinySpectrum.app` and move it to `/Applications`.
3. Connect the tinySA Ultra directly over USB.
4. Close any other software using its serial port, then open TinySpectrum.

The current release is ad-hoc signed. On first launch, macOS may require confirmation in **System Settings → Privacy & Security** because the app is not yet notarized with an Apple Developer ID.

TinySpectrum requires **macOS 14 Sonoma or newer**.

## Quick start

1. Start the tinySA normally in USB serial/console mode—not firmware-update mode.
2. Connect it to the Mac and wait for the green connection indicator.
3. Select a preset or enter a start and stop frequency.
4. Choose **Scan** for a single sweep or **Continuous** for a timeline.
5. Enable **Peak Hold** to retain the strongest signals.
6. Select **WWB** beside a saved scan when you are ready to export.

Scans and custom presets are stored at:

```text
~/Library/Application Support/TinySpectrum/scans.json
```

## Supported resolution bandwidths

TinySpectrum exposes the manual RBWs supported by tinySA Ultra firmware:

`200 Hz` · `1 kHz` · `3 kHz` · `10 kHz` · `30 kHz` · `100 kHz` · `300 kHz` · `600 kHz` · `850 kHz`

The ZS405 range is conservatively limited to 5.3 GHz. Hardware capabilities and calibrated ranges can differ between Ultra and Ultra+ models.

## Build from source

Requirements:

- macOS 14 or newer
- Xcode Command Line Tools with Swift 6

```sh
git clone https://github.com/iron-LAN/TinySpectrum.git
cd TinySpectrum
chmod +x scripts/build-app.sh
./scripts/build-app.sh
cp -R dist/TinySpectrum.app /Applications/
```

Run the test suite with:

```sh
swift test
```

## Updates and releases

Stable releases are built on macOS by GitHub Actions, packaged as a `.zip`, signed for Sparkle update verification, and published on the [Releases page](https://github.com/iron-LAN/TinySpectrum/releases).

Inside TinySpectrum, use **Check for Updates…** from the application menu or allow the automatic launch check to notify you when a newer stable version is available.

## Privacy

TinySpectrum does not upload spectrum measurements, presets, or scan history. Location access is optional and only resolves an approximate city name for convenient WWB export filenames.

## Contributing

Bug reports and feature ideas are welcome through [GitHub Issues](https://github.com/iron-LAN/TinySpectrum/issues). Pull requests target the protected `main` branch and should keep the app buildable with `swift test`.
