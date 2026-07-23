# TinySpectrum

A free, local macOS spectrum viewer and scanner for tinySA Ultra / Ultra+ over USB serial.

## Build and install

Requires macOS 14 or newer and Apple Command Line Tools.

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
cp -R dist/TinySpectrum.app /Applications/
```

The development build is ad-hoc signed. macOS may ask you to confirm opening an app from an unidentified developer the first time. A public release should use a Developer ID certificate and Apple notarization.

## Connect

1. Start the tinySA normally (USB serial/console mode, not firmware-update mode).
2. Connect it directly by USB and close any other app using its serial port.
3. Open TinySpectrum. It discovers and connects to the device automatically.
4. Choose a range and resolution bandwidth, then press **Scan** or **Continuous**.

Scans and custom presets are stored only in `~/Library/Application Support/TinySpectrum/`.

## Hardware notes

The Ultra ZS405 is calibrated to 5.3 GHz in Ultra mode; Ultra+ models differ. The initial app range is conservative for ZS405. Manual RBWs supported by Ultra firmware are 0.2, 1, 3, 10, 30, 100, 300, 600 and 850 kHz. TinySpectrum starts at 30 kHz and uses the selected RBW for both normal and continuous scans; continuous captures use 145 points for faster refresh. Narrow RBW over a wide span can take substantially longer.

Use the **Shure** button beside any scan to create a headerless two-column WWB CSV containing frequency in MHz and amplitude in dBm. For continuous sessions, the frame selected on the timeline is exported. Export names use `Preset_Resolution_City.csv`; approximate location permission is used only to obtain the city name.
