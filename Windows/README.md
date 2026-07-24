# TinySpectrum for Windows

The Windows application is a native Avalonia companion to the macOS TinySpectrum app. It targets Windows 10/11 x64 and communicates with tinySA Ultra devices through a USB COM port.

## Current beta features

- COM-port discovery and tinySA connection
- Single and continuous spectrum scans
- Demo mode for testing without connected hardware
- Adaptive RBW and continuous-scan intervals
- Cumulative Peak Hold and timeline playback
- Only one visible continuous session, with regular scan overlays
- Local scan and preset persistence in `%LOCALAPPDATA%\TinySpectrum`
- WWB-compatible CSV and one-antenna `.sdb3` timeline exports
- Self-contained Windows x64 package; no separate .NET installation required

## Run from source

Install the .NET 10 SDK, then run:

```powershell
dotnet run --project Windows/TinySpectrum.Windows/TinySpectrum.Windows.csproj
```

Choose a COM port and select **Connect**, or select **Demo** to exercise scanning without hardware.

## Test

```powershell
dotnet test Windows/TinySpectrum.Windows.slnx -c Release
```

## Package

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-windows.ps1 -Version 0.1.0-beta.1
```

The self-contained archive is written to `dist/TinySpectrum-0.1.0-beta.1-win-x64.zip`.
