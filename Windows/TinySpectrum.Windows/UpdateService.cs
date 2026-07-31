using System.Diagnostics;
using System.IO.Compression;
using System.Net.Http.Json;
using System.Reflection;
using System.Text.Json.Serialization;
using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;

namespace TinySpectrum.Windows;

public sealed record AppUpdate(Version Version, string Tag, string DownloadUrl, string ReleaseUrl);

public sealed class UpdateService
{
    private const string LatestReleaseApi = "https://api.github.com/repos/iron-LAN/TinySpectrum/releases/latest";
    private readonly HttpClient _client = new();

    public UpdateService()
    {
        _client.DefaultRequestHeaders.UserAgent.ParseAdd("TinySpectrum-Windows");
        _client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
    }

    public Version CurrentVersion => Assembly.GetEntryAssembly()?.GetName().Version ?? new Version(0, 0);
    public bool CurrentIsPrerelease =>
        (Assembly.GetEntryAssembly()?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "").Contains('-');

    public static bool IsUpdateAvailable(Version current, bool currentIsPrerelease, Version release) =>
        release > current || release == current && currentIsPrerelease;

    public async Task<AppUpdate?> CheckAsync(CancellationToken cancellationToken = default)
    {
        var release = await _client.GetFromJsonAsync<GitHubRelease>(LatestReleaseApi, cancellationToken);
        if (release is null || release.Draft || release.Prerelease || !TryVersion(release.TagName, out var version) ||
            !IsUpdateAvailable(CurrentVersion, CurrentIsPrerelease, version))
            return null;
        var asset = release.Assets.FirstOrDefault(item => item.Name.EndsWith("win-x64.zip", StringComparison.OrdinalIgnoreCase));
        return asset is null ? null : new(version, release.TagName, asset.DownloadUrl, release.HtmlUrl);
    }

    public async Task InstallAsync(AppUpdate update, IProgress<double>? progress = null, CancellationToken cancellationToken = default)
    {
        var updateRoot = Path.Combine(Path.GetTempPath(), $"TinySpectrum-update-{Guid.NewGuid():N}");
        var archivePath = Path.Combine(updateRoot, "update.zip");
        var payloadPath = Path.Combine(updateRoot, "payload");
        Directory.CreateDirectory(payloadPath);

        using (var response = await _client.GetAsync(update.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, cancellationToken))
        {
            response.EnsureSuccessStatusCode();
            var total = response.Content.Headers.ContentLength;
            await using var input = await response.Content.ReadAsStreamAsync(cancellationToken);
            await using var output = File.Create(archivePath);
            var buffer = new byte[128 * 1024];
            long received = 0;
            while (true)
            {
                var count = await input.ReadAsync(buffer, cancellationToken);
                if (count == 0) break;
                await output.WriteAsync(buffer.AsMemory(0, count), cancellationToken);
                received += count;
                if (total is > 0) progress?.Report((double)received / total.Value);
            }
        }
        ZipFile.ExtractToDirectory(archivePath, payloadPath, true);

        var targetPath = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        var executablePath = Environment.ProcessPath ?? Path.Combine(targetPath, "TinySpectrum.exe");
        var scriptPath = Path.Combine(updateRoot, "install-update.ps1");
        File.WriteAllText(scriptPath, InstallerScript);

        var installer = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        foreach (var argument in new[]
                 {
                     "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", scriptPath,
                     "-ParentProcessId", Environment.ProcessId.ToString(), "-Source", payloadPath, "-Target", targetPath,
                     "-Executable", executablePath
                 }) installer.ArgumentList.Add(argument);
        var process = Process.Start(installer) ?? throw new InvalidOperationException("Windows could not start the TinySpectrum updater.");
        await Task.Delay(500, cancellationToken);
        if (process.HasExited)
            throw new InvalidOperationException($"The TinySpectrum updater stopped before installation (exit code {process.ExitCode}).");
        if (Application.Current?.ApplicationLifetime is IClassicDesktopStyleApplicationLifetime lifetime) lifetime.Shutdown();
    }

    public const string InstallerScript = """
param([int]$ParentProcessId, [string]$Source, [string]$Target, [string]$Executable)
$ErrorActionPreference = 'Stop'
$log = Join-Path ([IO.Path]::GetTempPath()) 'TinySpectrum-update.log'

try {
    "$(Get-Date -Format o) Starting update from '$Source' to '$Target'." | Set-Content -LiteralPath $log
    Wait-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 750

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "The downloaded update payload is missing." }
    if (-not (Test-Path -LiteralPath $Target -PathType Container)) { throw "The TinySpectrum installation folder is missing." }

    $newExecutable = Get-ChildItem -LiteralPath $Source -Filter 'TinySpectrum.exe' -File -Recurse | Select-Object -First 1
    if ($null -eq $newExecutable) { throw "The downloaded update does not contain TinySpectrum.exe." }
    $payloadRoot = $newExecutable.Directory.FullName

    $copied = $false
    for ($attempt = 1; $attempt -le 15 -and -not $copied; $attempt++) {
        try {
            Get-ChildItem -LiteralPath $payloadRoot -Force | Copy-Item -Destination $Target -Recurse -Force -ErrorAction Stop
            $copied = $true
        } catch {
            if ($attempt -eq 15) { throw }
            Start-Sleep -Milliseconds 500
        }
    }

    $installedExecutable = Join-Path $Target 'TinySpectrum.exe'
    if (-not (Test-Path -LiteralPath $installedExecutable -PathType Leaf)) { throw "TinySpectrum.exe was not installed." }
    Unblock-File -LiteralPath $installedExecutable -ErrorAction SilentlyContinue
    "$(Get-Date -Format o) Update installed successfully." | Add-Content -LiteralPath $log
    Start-Process -FilePath $installedExecutable -WorkingDirectory $Target
} catch {
    "$(Get-Date -Format o) Update failed: $($_.Exception.Message)`n$($_.ScriptStackTrace)" | Add-Content -LiteralPath $log
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("TinySpectrum could not install the update.`n`n$($_.Exception.Message)`n`nDetails: $log", 'TinySpectrum Update') | Out-Null
    exit 1
}
""";

    private static bool TryVersion(string tag, out Version version) =>
        Version.TryParse(tag.TrimStart('v', 'V').Split('-', 2)[0], out version!);

    private sealed record GitHubRelease(
        [property: JsonPropertyName("tag_name")] string TagName,
        [property: JsonPropertyName("html_url")] string HtmlUrl,
        [property: JsonPropertyName("draft")] bool Draft,
        [property: JsonPropertyName("prerelease")] bool Prerelease,
        [property: JsonPropertyName("assets")] List<GitHubAsset> Assets);

    private sealed record GitHubAsset(
        [property: JsonPropertyName("name")] string Name,
        [property: JsonPropertyName("browser_download_url")] string DownloadUrl);
}
