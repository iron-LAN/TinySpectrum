using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Avalonia.Threading;

namespace TinySpectrum.Windows;

public sealed class MainViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly TinySaSerial _serial = new();
    private readonly ScanStore _store = new();
    private readonly DispatcherTimer _portTimer;
    private CancellationTokenSource? _scanCancellation;
    private bool _timingDrivenByInterval;
    private bool _isScanning;
    private bool _isConnected;
    private bool _isDemo;
    private bool _peakHoldEnabled;
    private string _status = "Connect a tinySA Ultra or start Demo mode";
    private string? _selectedPort;
    private double _startMhz = 470;
    private double _stopMhz = 700;
    private RbwOption _selectedRbw = RbwOption.All[4];
    private IntervalOption _selectedInterval = IntervalOption.All[2];
    private double? _intervalProgress;
    private double? _nextScanRemaining;
    private int _timelineIndex;

    public ObservableCollection<string> Ports { get; } = [];
    public ObservableCollection<SpectrumScan> Scans { get; } = [];
    public ObservableCollection<ScanPreset> Presets { get; } = [];
    public IReadOnlyList<RbwOption> RbwOptions => RbwOption.All;
    public IReadOnlyList<IntervalOption> IntervalOptions => IntervalOption.All;

    public AsyncCommand ConnectCommand { get; }
    public AsyncCommand ScanCommand { get; }
    public AsyncCommand ContinuousCommand { get; }
    public RelayCommand StopCommand { get; }
    public RelayCommand DemoCommand { get; }
    public RelayCommand ClearCommand { get; }

    public MainViewModel()
    {
        var stored = _store.Load();
        foreach (var scan in stored.Scans) { scan.IsVisible = false; Scans.Add(scan); }
        foreach (var preset in stored.Presets.Count > 0 ? stored.Presets : DefaultPresets()) Presets.Add(preset);

        ConnectCommand = new(ConnectAsync, () => !IsScanning && SelectedPort is not null);
        ScanCommand = new(() => BeginScanAsync(false), () => CanScan);
        ContinuousCommand = new(() => BeginScanAsync(true), () => CanScan);
        StopCommand = new(Stop, () => IsScanning);
        DemoCommand = new(EnableDemo, () => !IsScanning);
        ClearCommand = new(() => { foreach (var scan in Scans) scan.IsVisible = false; NotifySpectrum(); });

        RefreshPorts();
        _portTimer = new DispatcherTimer(TimeSpan.FromSeconds(2), DispatcherPriority.Background, (_, _) => RefreshPorts());
        _portTimer.Start();
        SynchronizeInterval();
    }

    public string? SelectedPort { get => _selectedPort; set { Set(ref _selectedPort, value); ConnectCommand.Raise(); } }
    public bool IsConnected { get => _isConnected; private set { Set(ref _isConnected, value); RaiseCommands(); OnPropertyChanged(nameof(ConnectionText)); } }
    public string ConnectionText => IsDemo ? "DEMO" : IsConnected ? _serial.PortName ?? "CONNECTED" : "DISCONNECTED";
    public bool IsDemo { get => _isDemo; private set { Set(ref _isDemo, value); RaiseCommands(); OnPropertyChanged(nameof(ConnectionText)); } }
    public bool IsScanning { get => _isScanning; private set { Set(ref _isScanning, value); RaiseCommands(); } }
    public bool CanScan => (IsConnected || IsDemo) && !IsScanning;
    public string Status { get => _status; private set => Set(ref _status, value); }
    public double StartMhz { get => _startMhz; set { if (Set(ref _startMhz, Math.Max(.1, value))) RangeChanged(); } }
    public double StopMhz { get => _stopMhz; set { if (Set(ref _stopMhz, Math.Max(StartMhz + .001, value))) RangeChanged(); } }
    public RbwOption SelectedRbw
    {
        get => _selectedRbw;
        set { if (!Set(ref _selectedRbw, value)) return; _timingDrivenByInterval = false; SynchronizeInterval(); }
    }
    public IntervalOption SelectedInterval
    {
        get => _selectedInterval;
        set { if (!Set(ref _selectedInterval, value)) return; _timingDrivenByInterval = true; SynchronizeRbw(); }
    }
    public string EstimatedSweepText => $"~{DurationText(EstimatedSweepDuration)} sweep";
    public double EstimatedSweepDuration => SweepEstimator.Duration((StopMhz - StartMhz) * 1e6, SelectedRbw);
    public bool PeakHoldEnabled { get => _peakHoldEnabled; set { if (Set(ref _peakHoldEnabled, value)) NotifySpectrum(); } }
    public double? IntervalProgress { get => _intervalProgress; private set => Set(ref _intervalProgress, value); }
    public double? NextScanRemaining { get => _nextScanRemaining; private set { Set(ref _nextScanRemaining, value); OnPropertyChanged(nameof(CountdownText)); } }
    public string CountdownText => NextScanRemaining is { } seconds ? DurationText(seconds) : "";
    public int TimelineIndex { get => _timelineIndex; set { if (Set(ref _timelineIndex, Math.Max(0, value))) NotifySpectrum(); } }
    public int TimelineMaximum => Math.Max(0, VisibleContinuous?.CaptureCount - 1 ?? 0);
    public SpectrumScan? VisibleContinuous => Scans.FirstOrDefault(x => x.IsContinuous && x.IsVisible);
    public int VisibleCount => Scans.Count(x => x.IsVisible);

    private async Task ConnectAsync()
    {
        if (SelectedPort is null) return;
        try
        {
            Status = $"Connecting to {SelectedPort}…";
            await _serial.ConnectAsync(SelectedPort);
            IsDemo = false; IsConnected = true; Status = $"tinySA connected on {SelectedPort}";
        }
        catch (Exception exception) { IsConnected = false; Status = exception.Message; }
    }

    private void EnableDemo()
    {
        IsDemo = true; IsConnected = false; Status = "Demo mode — generated RF data";
    }

    private async Task BeginScanAsync(bool continuous)
    {
        if (!CanScan) return;
        IsScanning = true;
        _scanCancellation = new();
        SpectrumScan? session = null;
        try
        {
            do
            {
                var started = DateTimeOffset.Now;
                IntervalProgress = null; NextScanRemaining = null;
                Status = $"Scanning {FrequencyText.Short(StartMhz * 1e6)} – {FrequencyText.Short(StopMhz * 1e6)}…";
                var points = IsDemo
                    ? await DemoScanAsync(StartMhz * 1e6, StopMhz * 1e6, continuous ? 145 : 450, _scanCancellation.Token)
                    : await _serial.ScanAsync(StartMhz * 1e6, StopMhz * 1e6, SelectedRbw, continuous ? 145 : 450, _scanCancellation.Token);
                var capture = new ScanCapture(DateTimeOffset.Now, points.ToList());
                if (continuous && session is not null)
                {
                    session.Points = points.ToList(); session.Captures!.Add(capture); session.NotifyUpdated();
                }
                else
                {
                    session = new SpectrumScan
                    {
                        StartHz = StartMhz * 1e6,
                        StopHz = StopMhz * 1e6,
                        Date = capture.Date,
                        Rbw = continuous ? $"{SelectedRbw.Label} • every {SelectedInterval.Label} • 145 pts" : SelectedRbw.Label,
                        Points = points.ToList(),
                        Captures = continuous ? [capture] : null
                    };
                    Scans.Insert(0, session); ShowScan(session);
                }
                Status = continuous ? $"Continuous scan • {session.CaptureCount} captures" : $"Captured {points.Count} points";
                Save(); NotifySpectrum();
                if (!continuous) break;

                var deadline = started.AddSeconds(SelectedInterval.Seconds);
                while (DateTimeOffset.Now < deadline)
                {
                    _scanCancellation.Token.ThrowIfCancellationRequested();
                    var remaining = (deadline - DateTimeOffset.Now).TotalSeconds;
                    NextScanRemaining = Math.Max(0, remaining);
                    IntervalProgress = Math.Clamp(1 - remaining / SelectedInterval.Seconds, 0, 1);
                    await Task.Delay(100, _scanCancellation.Token);
                }
            } while (!_scanCancellation.IsCancellationRequested);
        }
        catch (OperationCanceledException) { Status = "Scan stopped"; }
        catch (Exception exception) { Status = exception.Message; }
        finally
        {
            IntervalProgress = null; NextScanRemaining = null; IsScanning = false;
            _scanCancellation.Dispose(); _scanCancellation = null;
        }
    }

    private void Stop()
    {
        Status = "Stopping scan…";
        _scanCancellation?.Cancel();
        _serial.Abort();
    }

    public void ToggleVisibility(SpectrumScan scan)
    {
        if (scan.IsVisible) scan.IsVisible = false; else ShowScan(scan);
        NotifySpectrum();
    }

    public void DeleteScan(SpectrumScan scan)
    {
        Scans.Remove(scan); Save(); NotifySpectrum();
    }

    private void ShowScan(SpectrumScan scan)
    {
        if (scan.IsContinuous)
        {
            foreach (var other in Scans.Where(x => x.IsContinuous && x != scan)) other.IsVisible = false;
            TimelineIndex = Math.Max(0, scan.CaptureCount - 1);
        }
        scan.IsVisible = true;
    }

    public void ApplyPreset(ScanPreset preset) { StartMhz = preset.StartHz / 1e6; StopMhz = preset.StopHz / 1e6; }

    private static async Task<IReadOnlyList<ScanPoint>> DemoScanAsync(double start, double stop, int count, CancellationToken token)
    {
        await Task.Delay(650, token);
        var phase = DateTimeOffset.Now.ToUnixTimeMilliseconds() / 1800.0;
        return Enumerable.Range(0, count).Select(i =>
        {
            var frequency = start + (stop - start) * i / (count - 1);
            var noise = -102 + Random.Shared.NextDouble() * 5;
            var peak1 = 23 * Math.Exp(-Math.Pow((i - count * (.32 + .02 * Math.Sin(phase))) / 5.0, 2));
            var peak2 = 15 * Math.Exp(-Math.Pow((i - count * .74) / 3.0, 2));
            return new ScanPoint(frequency, noise + peak1 + peak2);
        }).ToArray();
    }

    private void RefreshPorts()
    {
        var current = TinySaSerial.Ports();
        if (Ports.SequenceEqual(current)) return;
        Ports.Clear(); foreach (var port in current) Ports.Add(port);
        if (SelectedPort is null || !Ports.Contains(SelectedPort)) SelectedPort = Ports.FirstOrDefault();
    }

    private void RangeChanged()
    {
        if (_timingDrivenByInterval) SynchronizeRbw(); else SynchronizeInterval();
        OnPropertyChanged(nameof(EstimatedSweepDuration)); OnPropertyChanged(nameof(EstimatedSweepText));
    }
    private void SynchronizeRbw()
    {
        _selectedRbw = SweepEstimator.Finest((StopMhz - StartMhz) * 1e6, SelectedInterval);
        OnPropertyChanged(nameof(SelectedRbw)); OnPropertyChanged(nameof(EstimatedSweepDuration)); OnPropertyChanged(nameof(EstimatedSweepText));
    }
    private void SynchronizeInterval()
    {
        _selectedInterval = SweepEstimator.Shortest((StopMhz - StartMhz) * 1e6, SelectedRbw);
        OnPropertyChanged(nameof(SelectedInterval)); OnPropertyChanged(nameof(EstimatedSweepDuration)); OnPropertyChanged(nameof(EstimatedSweepText));
    }
    private void NotifySpectrum()
    {
        OnPropertyChanged(nameof(VisibleContinuous)); OnPropertyChanged(nameof(TimelineMaximum));
        OnPropertyChanged(nameof(VisibleCount)); OnPropertyChanged("Spectrum");
    }
    private void Save() => _store.Save(Scans, Presets);
    private void RaiseCommands() { ConnectCommand.Raise(); ScanCommand.Raise(); ContinuousCommand.Raise(); StopCommand.RaiseCanExecuteChanged(); DemoCommand.RaiseCanExecuteChanged(); }
    private static string DurationText(double duration)
    {
        var seconds = Math.Max(1, (int)Math.Round(duration));
        return seconds < 60 ? $"{seconds}s" : seconds % 60 == 0 ? $"{seconds / 60}m" : $"{seconds / 60}m {seconds % 60}s";
    }
    private static IEnumerable<ScanPreset> DefaultPresets() =>
    [new("FM Broadcast", 87.5e6, 108e6), new("ISM 433", 433e6, 435e6), new("ISM 868", 863e6, 870e6), new("UHF", 470e6, 700e6)];

    public event PropertyChangedEventHandler? PropertyChanged;
    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value; OnPropertyChanged(name); return true;
    }
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));

    public void Dispose() { _portTimer.Stop(); _scanCancellation?.Cancel(); _serial.Dispose(); }
}
