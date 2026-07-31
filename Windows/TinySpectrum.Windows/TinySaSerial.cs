using System.Globalization;
using System.IO.Ports;
using System.Text;

namespace TinySpectrum.Windows;

public sealed class TinySaSerial : IDisposable
{
    private SerialPort? _port;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public bool IsConnected => _port?.IsOpen == true;
    public TinySaProfile Profile { get; private set; } = TinySaProfile.Regular;
    public string? PortName => _port?.PortName;
    public static IReadOnlyList<string> Ports() => SerialPort.GetPortNames().OrderBy(x => x).ToArray();

    public async Task ConnectAsync(string portName, CancellationToken cancellationToken = default)
    {
        await DisconnectAsync();
        var port = new SerialPort(portName, 115200, Parity.None, 8, StopBits.One)
        {
            Handshake = Handshake.None,
            NewLine = "\r\n",
            ReadTimeout = 250,
            WriteTimeout = 1000,
            DtrEnable = true,
            RtsEnable = false
        };
        await Task.Run(port.Open, cancellationToken);
        port.DiscardInBuffer();
        port.DiscardOutBuffer();
        _port = port;
        try { Profile = TinySaProfile.FromInfo(await CommandAsync("info", TimeSpan.FromSeconds(3), cancellationToken)); }
        catch { Profile = TinySaProfile.Regular; }
        if (Profile.IsUltra) await CommandAsync("ultra on", TimeSpan.FromSeconds(3), cancellationToken);
    }

    public Task DisconnectAsync()
    {
        if (_port is { } port)
        {
            try { if (port.IsOpen) port.Close(); } catch { }
            port.Dispose();
            _port = null;
        }
        return Task.CompletedTask;
    }

    public async Task<IReadOnlyList<ScanPoint>> ScanAsync(double startHz, double stopHz, RbwOption rbw, int points, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            EnsureConnected();
            await ConfigureRangeCoreAsync(startHz, stopHz, cancellationToken);
            if (!Profile.Supports(rbw)) throw new InvalidOperationException($"{Profile.Name} supports resolution bandwidths from 3 to 600 kHz.");
            await CommandAsync("abort on", TimeSpan.FromSeconds(3), cancellationToken);
            await CommandAsync($"rbw {rbw.Command}", TimeSpan.FromSeconds(3), cancellationToken);
            points = Math.Clamp(points, 2, Profile.MaximumPoints);
            var response = await CommandAsync($"scan {(long)startHz} {(long)stopHz} {points} 3", TimeSpan.FromMinutes(10), cancellationToken);
            var values = new List<ScanPoint>();
            foreach (var line in response.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
            {
                var tokens = line.Trim().Replace("-:.0", "-10.0", StringComparison.Ordinal)
                    .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
                if (tokens.Length >= 2 && double.TryParse(tokens[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var frequency)
                    && double.TryParse(tokens[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var level))
                    values.Add(new(frequency, level));
            }
            if (values.Count < 2) throw new IOException("The tinySA returned no readable frequency/level measurement pairs.");
            return values;
        }
        finally { _gate.Release(); }
    }

    public async Task ConfigureRangeAsync(double startHz, double stopHz, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try { await ConfigureRangeCoreAsync(startHz, stopHz, cancellationToken); }
        finally { _gate.Release(); }
    }

    private async Task ConfigureRangeCoreAsync(double startHz, double stopHz, CancellationToken cancellationToken)
    {
        EnsureConnected();
        if (startHz < 100_000 || stopHz > Profile.MaximumHz || stopHz <= startHz)
            throw new InvalidOperationException($"The selected range is outside the supported range of {Profile.Name}.");
        if (Profile.InputMode(startHz, stopHz) is { } mode)
            await CommandAsync($"mode {mode} input", TimeSpan.FromSeconds(3), cancellationToken);
        await CommandAsync($"sweep start {(long)startHz}", TimeSpan.FromSeconds(3), cancellationToken);
        await CommandAsync($"sweep stop {(long)stopHz}", TimeSpan.FromSeconds(3), cancellationToken);
    }

    public async Task<int> BatteryVoltageAsync(CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var response = await CommandAsync("vbat", TimeSpan.FromSeconds(3), cancellationToken);
            var values = response.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
                .Select(token => int.TryParse(token, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) ? value : -1);
            var millivolts = values.FirstOrDefault(value => value is >= 2500 and <= 5000);
            if (millivolts == 0) throw new IOException("The tinySA returned no readable battery voltage.");
            return millivolts;
        }
        finally { _gate.Release(); }
    }

    public void Abort()
    {
        try { if (_port?.IsOpen == true) _port.Write("abort\r\n"); } catch { }
    }

    private async Task<string> CommandAsync(string command, TimeSpan timeout, CancellationToken cancellationToken)
    {
        EnsureConnected();
        _port!.DiscardInBuffer();
        _port.Write(command + "\r\n");
        var text = new StringBuilder();
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (_port.BytesToRead > 0)
            {
                text.Append(_port.ReadExisting());
                if (text.ToString().Contains("ch>", StringComparison.Ordinal)) return text.ToString();
            }
            await Task.Delay(15, cancellationToken);
        }
        throw new TimeoutException($"The tinySA did not finish '{command}' in time.");
    }

    private void EnsureConnected()
    {
        if (!IsConnected) throw new IOException("Connect a tinySA before scanning.");
    }

    public void Dispose()
    {
        _ = DisconnectAsync();
        _gate.Dispose();
    }
}
