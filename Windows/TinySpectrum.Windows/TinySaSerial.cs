using System.Globalization;
using System.IO.Ports;
using System.Text;

namespace TinySpectrum.Windows;

public sealed class TinySaSerial : IDisposable
{
    private SerialPort? _port;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public bool IsConnected => _port?.IsOpen == true;
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
            await CommandAsync("abort on", TimeSpan.FromSeconds(3), cancellationToken);
            await CommandAsync($"rbw {rbw.Command}", TimeSpan.FromSeconds(3), cancellationToken);
            var response = await CommandAsync($"scan {(long)startHz} {(long)stopHz} {points} 2", TimeSpan.FromMinutes(10), cancellationToken);
            var levels = new List<double>();
            foreach (var line in response.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
            {
                var token = line.Trim().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
                if (token is null) continue;
                token = token.Replace("-:.0", "-10.0", StringComparison.Ordinal);
                if (double.TryParse(token, NumberStyles.Float, CultureInfo.InvariantCulture, out var level)) levels.Add(level);
            }
            if (levels.Count < 2) throw new IOException("The tinySA returned no readable measurement points.");
            return levels.Select((level, index) => new ScanPoint(
                startHz + (stopHz - startHz) * index / (levels.Count - 1), level)).ToArray();
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
