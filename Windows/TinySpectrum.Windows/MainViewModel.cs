using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Globalization;
using Avalonia.Threading;

namespace TinySpectrum.Windows;

public sealed class MainViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly TinySaSerial _serial = new();
    private readonly ScanStore _store = new();
    private readonly DispatcherTimer _portTimer;
    private CancellationTokenSource? _scanCancellation;
    private bool _connectInFlight;
    private bool _batteryPollInFlight;
    private bool _timingDrivenByInterval;
    private bool _isScanning;
    private bool _isConnected;
    private bool _peakHoldEnabled;
    private string _status = "Looking for TinySA…";
    private string? _selectedPort;
    private string _exportLocation = "UnknownLocation";
    private string _presetName = "";
    private double _startMhz = 470;
    private double _stopMhz = 700;
    private string _startMhzInput = "470";
    private string _stopMhzInput = "700";
    private RbwOption _selectedRbw = RbwOption.All[4];
    private IntervalOption _selectedInterval = IntervalOption.All[2];
    private double? _intervalProgress;
    private double? _nextScanRemaining;
    private int _timelineIndex;
    private int? _batteryMillivolts;
    private DateTimeOffset _lastBatteryPoll = DateTimeOffset.MinValue;

    public ObservableCollection<string> Ports { get; } = [];
    public ObservableCollection<SpectrumScan> Scans { get; } = [];
    public ObservableCollection<ScanPreset> Presets { get; } = [];
    public IReadOnlyList<RbwOption> RbwOptions => RbwOption.All;
    public IReadOnlyList<IntervalOption> IntervalOptions => IntervalOption.All;

    public AsyncCommand ScanCommand { get; }
    public AsyncCommand ContinuousCommand { get; }
    public RelayCommand StopCommand { get; }
    public RelayCommand SetRangeCommand { get; }
    public RelayCommand SavePresetCommand { get; }
    public RelayCommand ClearCommand { get; }

    public MainViewModel()
    {
        var stored = _store.Load();
        foreach (var scan in stored.Scans) { scan.IsVisible = false; Scans.Add(scan); }
        RefreshScanColors();
        foreach (var preset in stored.Presets.Count > 0 ? stored.Presets : DefaultPresets()) Presets.Add(preset);

        ScanCommand = new(() => BeginScanAsync(false), () => CanScan);
        ContinuousCommand = new(() => BeginScanAsync(true), () => CanScan);
        StopCommand = new(Stop, () => IsScanning);
        SetRangeCommand = new(SetRange, () => !IsScanning);
        SavePresetCommand = new(SavePreset, () => !string.IsNullOrWhiteSpace(PresetName));
        ClearCommand = new(() => { foreach (var scan in Scans) scan.IsVisible = false; NotifySpectrum(); });

        _ = RefreshPortsAsync();
        _portTimer = new DispatcherTimer(TimeSpan.FromSeconds(2), DispatcherPriority.Background, async (_, _) => await RefreshPortsAsync());
        _portTimer.Start();
        SynchronizeInterval();
    }

    public string? SelectedPort { get => _selectedPort; set => Set(ref _selectedPort, value); }
    public string ExportLocation { get => _exportLocation; set => Set(ref _exportLocation, value); }
    public bool IsConnected { get => _isConnected; private set { Set(ref _isConnected, value); RaiseCommands(); OnPropertyChanged(nameof(ConnectionText)); OnPropertyChanged(nameof(ConnectionColor)); } }
    public string ConnectionText => IsConnected ? _serial.PortName ?? "CONNECTED" : "LOOKING FOR TINYSA";
    public string ConnectionColor => IsConnected ? "#32E38A" : "#7890A2";
    public string BatteryText => _batteryMillivolts is { } millivolts
        ? $"~{BatteryPercent(millivolts)}%  •  {millivolts / 1000.0:0.00} V"
        : "";
    public bool IsScanning { get => _isScanning; private set { Set(ref _isScanning, value); RaiseCommands(); } }
    public bool CanScan => IsConnected && !IsScanning;
    public string PresetName { get => _presetName; set { if (Set(ref _presetName, value)) SavePresetCommand.RaiseCanExecuteChanged(); } }
    public string Status { get => _status; private set => Set(ref _status, value); }
    public double StartMhz { get => _startMhz; set { if (Set(ref _startMhz, Math.Max(.1, value))) RangeChanged(); } }
    public double StopMhz { get => _stopMhz; set { if (Set(ref _stopMhz, Math.Max(StartMhz + .001, value))) RangeChanged(); } }
    public string StartMhzInput { get => _startMhzInput; set => Set(ref _startMhzInput, value); }
    public string StopMhzInput { get => _stopMhzInput; set => Set(ref _stopMhzInput, value); }
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
    public bool HasVisibleContinuous => VisibleContinuous is not null;
    public int VisibleCount => Scans.Count(x => x.IsVisible);

    private async Task ConnectAsync()
    {
        if (SelectedPort is null || _connectInFlight || IsConnected) return;
        _connectInFlight = true;
        try
        {
            Status = "Connecting to TinySA…";
            await _serial.ConnectAsync(SelectedPort);
            IsConnected = true; _lastBatteryPoll = DateTimeOffset.MinValue; Status = "TinySA connected";
        }
        catch (Exception exception) { IsConnected = false; Status = exception.Message; }
        finally { _connectInFlight = false; }
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
                var points = await _serial.ScanAsync(StartMhz * 1e6, StopMhz * 1e6, SelectedRbw, continuous ? 145 : 450, _scanCancellation.Token);
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
                    Scans.Insert(0, session); RefreshScanColors(); ShowScan(session);
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
        Scans.Remove(scan); RefreshScanColors(); Save(); NotifySpectrum();
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

    public void ApplyPreset(ScanPreset preset)
    {
        StartMhz = preset.StartHz / 1e6; StopMhz = preset.StopHz / 1e6;
        StartMhzInput = FormatMhz(StartMhz); StopMhzInput = FormatMhz(StopMhz);
    }

    public void DeletePreset(ScanPreset preset)
    {
        Presets.Remove(preset);
        Save();
    }

    private void SetRange()
    {
        if (!TryParseMhz(StartMhzInput, out var start) || !TryParseMhz(StopMhzInput, out var stop))
        {
            Status = "Enter valid start and stop frequencies in MHz";
            return;
        }
        StartMhz = Math.Clamp(start, .1, 5299.999);
        StopMhz = Math.Clamp(stop, StartMhz + .001, 5300);
        StartMhzInput = FormatMhz(StartMhz); StopMhzInput = FormatMhz(StopMhz);
        RangeChanged();
        Status = $"Range set to {FrequencyText.Short(StartMhz * 1e6)} – {FrequencyText.Short(StopMhz * 1e6)}";
    }

    private static bool TryParseMhz(string text, out double value) =>
        double.TryParse(text, NumberStyles.Float, CultureInfo.CurrentCulture, out value) ||
        double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out value);

    private static string FormatMhz(double value) => value.ToString("0.######", CultureInfo.CurrentCulture);

    private void RefreshScanColors()
    {
        for (var index = 0; index < Scans.Count; index++) Scans[index].DisplayColor = ScanPalette.At(index);
    }

    private void SavePreset()
    {
        var name = PresetName.Trim();
        if (name.Length == 0) return;
        Presets.Add(new(name, StartMhz * 1e6, StopMhz * 1e6));
        PresetName = "";
        Save();
    }

    private async Task RefreshPortsAsync()
    {
        var current = TinySaSerial.Ports();
        if (!Ports.SequenceEqual(current))
        {
            Ports.Clear(); foreach (var port in current) Ports.Add(port);
        }
        if (IsConnected && (_serial.PortName is null || !current.Contains(_serial.PortName)))
        {
            await _serial.DisconnectAsync();
            IsConnected = false;
            _batteryMillivolts = null; OnPropertyChanged(nameof(BatteryText));
            Status = "TinySA disconnected — looking for it…";
        }
        if (SelectedPort is null || !Ports.Contains(SelectedPort)) SelectedPort = Ports.FirstOrDefault();
        if (!IsConnected && !IsScanning && SelectedPort is not null) await ConnectAsync();
        else if (!IsConnected && SelectedPort is null) Status = "Looking for TinySA…";
        if (IsConnected && !IsScanning && !_batteryPollInFlight && DateTimeOffset.Now - _lastBatteryPoll >= TimeSpan.FromMinutes(1))
            await PollBatteryAsync();
    }

    private async Task PollBatteryAsync()
    {
        _batteryPollInFlight = true;
        _lastBatteryPoll = DateTimeOffset.Now;
        try { _batteryMillivolts = await _serial.BatteryVoltageAsync(); OnPropertyChanged(nameof(BatteryText)); }
        catch { }
        finally { _batteryPollInFlight = false; }
    }

    private static int BatteryPercent(int millivolts)
    {
        (int Millivolts, int Percent)[] curve = [(3400, 0), (3600, 10), (3700, 20), (3800, 40), (3900, 60), (4000, 80), (4100, 90), (4200, 100)];
        if (millivolts <= curve[0].Millivolts) return 0;
        if (millivolts >= curve[^1].Millivolts) return 100;
        for (var index = 1; index < curve.Length; index++)
        {
            if (millivolts > curve[index].Millivolts) continue;
            var low = curve[index - 1]; var high = curve[index];
            return low.Percent + (millivolts - low.Millivolts) * (high.Percent - low.Percent) / (high.Millivolts - low.Millivolts);
        }
        return 0;
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
        OnPropertyChanged(nameof(VisibleContinuous)); OnPropertyChanged(nameof(HasVisibleContinuous)); OnPropertyChanged(nameof(TimelineMaximum));
        OnPropertyChanged(nameof(VisibleCount)); OnPropertyChanged("Spectrum");
    }
    private void Save() => _store.Save(Scans, Presets);
    private void RaiseCommands() { ScanCommand.Raise(); ContinuousCommand.Raise(); StopCommand.RaiseCanExecuteChanged(); SetRangeCommand.RaiseCanExecuteChanged(); }
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
