# TinySpectrum for Windows

The Windows application is a native Avalonia companion to the macOS TinySpectrum app. It targets Windows 10/11 x64 and communicates with tinySA Ultra devices through a USB COM port.

## Current beta features

- Automatic COM-port discovery, connection, and reconnection
- Single and continuous spectrum scans
- Adaptive RBW and continuous-scan intervals
- Cumulative Peak Hold and timeline playback
- Horizontal trackpad/mouse-wheel zoom and drag-to-pan spectrum navigation
- Adaptive frequency labels down to 25 kHz detail
- Only one visible continuous session, with regular scan overlays
- Local scan and preset persistence in `%LOCALAPPDATA%\TinySpectrum`
- WWB-compatible CSV and one-antenna `.sdb3` timeline exports
- Export names in `DD-MM-YY_LOCATION_` format, ready for the user to complete
- Self-contained Windows x64 package; no separate .NET installation required

## Run from source

Install the .NET 10 SDK, then run:

```powershell
dotnet run --project Windows/TinySpectrum.Windows/TinySpectrum.Windows.csproj
```

The app automatically connects when it finds a tinySA Ultra COM port. Select **Demo** to exercise scanning without hardware.

## Test

```powershell
dotnet test Windows/TinySpectrum.Windows.slnx -c Release
```

## Package

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-windows.ps1 -Version 0.2.0-beta.8
```

The self-contained archive is written to `dist/TinySpectrum-0.2.0-beta.8-win-x64.zip`.
