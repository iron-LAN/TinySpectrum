using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;

namespace TinySpectrum.Windows;

public partial class MainWindow : Window
{
    private readonly UpdateService _updates = new();
    private bool _checkingForUpdates;
    private MainViewModel ViewModel => (MainViewModel)DataContext!;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainViewModel();
        Closed += (_, _) => ViewModel.Dispose();
        Opened += async (_, _) => await CheckForUpdatesAsync(false);
    }

    private void Preset_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: ScanPreset preset }) ViewModel.ApplyPreset(preset);
    }

    private void DeletePreset_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: ScanPreset preset }) ViewModel.DeletePreset(preset);
    }

    private void Visibility_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: SpectrumScan scan }) ViewModel.ToggleVisibility(scan);
    }

    private async void Export_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: SpectrumScan scan }) return;
        var extension = scan.IsContinuous ? "sdb3" : "csv";
        var baseName = ExportFileName.BaseName(scan.Date, ViewModel.ExportLocation);
        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = scan.IsContinuous ? "Export WWB timeline" : "Export WWB scan",
            SuggestedFileName = $"{baseName}.{extension}",
            FileTypeChoices = [new FilePickerFileType(extension.ToUpperInvariant()) { Patterns = [$"*.{extension}"] }]
        });
        if (file is null) return;
        await using var stream = await file.OpenWriteAsync();
        if (scan.IsContinuous) await WwbTimelineExporter.WriteAsync(scan, stream, baseName);
        else await WwbTimelineExporter.WriteCsvAsync(scan.Points, stream);
    }

    private void Delete_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: SpectrumScan scan }) ViewModel.DeleteScan(scan);
    }

    private async void CheckUpdates_Click(object? sender, RoutedEventArgs e) => await CheckForUpdatesAsync(true);

    private async Task CheckForUpdatesAsync(bool userInitiated)
    {
        if (_checkingForUpdates) return;
        _checkingForUpdates = true;
        try
        {
            var update = await _updates.CheckAsync();
            if (update is null)
            {
                if (userInitiated) await new MessageWindow("TinySpectrum is up to date", $"Version {_updates.CurrentVersion.ToString(3)} is the newest version.").ShowDialog(this);
                return;
            }
            var install = await new UpdateWindow(update).ShowDialog<bool>(this);
            if (!install) return;
            ViewModel.SetStatus($"Downloading TinySpectrum {update.Version}…");
            await _updates.InstallAsync(update);
        }
        catch (Exception exception)
        {
            if (userInitiated) await new MessageWindow("Unable to check for updates", exception.Message).ShowDialog(this);
        }
        finally { _checkingForUpdates = false; }
    }
}

internal sealed class UpdateWindow : Window
{
    public UpdateWindow(AppUpdate update)
    {
        Title = "TinySpectrum Update"; Width = 430; Height = 220; CanResize = false;
        var later = new Button { Content = "Later" };
        var install = new Button { Content = "Download and Install" };
        later.Click += (_, _) => Close(false); install.Click += (_, _) => Close(true);
        Content = new StackPanel
        {
            Margin = new(24), Spacing = 16,
            Children =
            {
                new TextBlock { Text = $"TinySpectrum {update.Version} is available", FontSize = 20, FontWeight = Avalonia.Media.FontWeight.Bold },
                new TextBlock { Text = "Download the Windows update, install it in place, and restart TinySpectrum?", TextWrapping = Avalonia.Media.TextWrapping.Wrap },
                new StackPanel { Orientation = Avalonia.Layout.Orientation.Horizontal, Spacing = 10, HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Right, Children = { later, install } }
            }
        };
    }
}

internal sealed class MessageWindow : Window
{
    public MessageWindow(string title, string message)
    {
        Title = title; Width = 410; Height = 190; CanResize = false;
        var okay = new Button { Content = "OK", HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Right };
        okay.Click += (_, _) => Close();
        Content = new StackPanel { Margin = new(24), Spacing = 16, Children = { new TextBlock { Text = title, FontSize = 19, FontWeight = Avalonia.Media.FontWeight.Bold }, new TextBlock { Text = message, TextWrapping = Avalonia.Media.TextWrapping.Wrap }, okay } };
    }
}
