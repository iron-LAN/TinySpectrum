using System.Text.Json;

namespace TinySpectrum.Windows;

public sealed class ScanStore
{
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = false };
    private readonly string _path = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TinySpectrum", "scans-windows.json");

    public StoredData Load()
    {
        try { return JsonSerializer.Deserialize<StoredData>(File.ReadAllText(_path), Options) ?? new(); }
        catch { return new(); }
    }

    public void Save(IEnumerable<SpectrumScan> scans, IEnumerable<ScanPreset> presets)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        var temporary = _path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(new StoredData(scans.ToList(), presets.ToList()), Options));
        File.Move(temporary, _path, true);
    }
}

public sealed record StoredData(List<SpectrumScan> Scans, List<ScanPreset> Presets)
{
    public StoredData() : this([], []) { }
}
