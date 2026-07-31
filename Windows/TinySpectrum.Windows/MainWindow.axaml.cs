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
        Opened += async (_, _) => { UpdateThemeButton(); await CheckForUpdatesAsync(false); };
    }

    private void Theme_Click(object? sender, RoutedEventArgs e) { App.ToggleTheme(); ViewModel.RefreshThemeColors(); UpdateThemeButton(); }
    private void UpdateThemeButton() => ThemeButton.Content = App.IsDark ? "☀  Light" : "☾  Dark";

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
        var baseName = ExportFileName.BaseName(scan.Date, ViewModel.ExportLocation, scan.CustomName);
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

    private async void Rename_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: SpectrumScan scan }) return;
        var name = await new RenameScanWindow(scan.CustomName ?? "").ShowDialog<string?>(this);
        if (name is not null) ViewModel.RenameScan(scan, name);
    }

    private async void DeleteAll_Click(object? sender, RoutedEventArgs e)
    {
        if (ViewModel.Scans.Count > 0 && await new ConfirmWindow("Delete all scans?", "This permanently removes every saved scan from the browser.").ShowDialog<bool>(this)) ViewModel.DeleteAllScans();
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
            var install = await new UpdateWindow(update, _updates.CurrentVersion).ShowDialog<bool>(this);
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

internal sealed class RenameScanWindow : Window
{
    public RenameScanWindow(string currentName)
    {
        Title = "Rename Scan"; Width = 410; Height = 190; CanResize = false;
        var input = new TextBox { Text = currentName, PlaceholderText = "Scan name" };
        var cancel = new Button { Content = "Cancel" }; var save = new Button { Content = "Save" };
        cancel.Click += (_, _) => Close(null); save.Click += (_, _) => Close(input.Text?.Trim() ?? "");
        Content = new StackPanel { Margin = new(24), Spacing = 16, Children = { new TextBlock { Text = "Rename scan", FontSize = 19, FontWeight = Avalonia.Media.FontWeight.Bold }, input, new StackPanel { Orientation = Avalonia.Layout.Orientation.Horizontal, Spacing = 10, HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Right, Children = { cancel, save } } } };
        Opened += (_, _) => { input.Focus(); input.SelectAll(); };
    }
}

internal sealed class ConfirmWindow : Window
{
    public ConfirmWindow(string title, string message)
    {
        Title = title; Width = 410; Height = 190; CanResize = false;
        var cancel = new Button { Content = "Cancel" }; var confirm = new Button { Content = "Delete All" };
        cancel.Click += (_, _) => Close(false); confirm.Click += (_, _) => Close(true);
        Content = new StackPanel { Margin = new(24), Spacing = 16, Children = { new TextBlock { Text = title, FontSize = 19, FontWeight = Avalonia.Media.FontWeight.Bold }, new TextBlock { Text = message, TextWrapping = Avalonia.Media.TextWrapping.Wrap }, new StackPanel { Orientation = Avalonia.Layout.Orientation.Horizontal, Spacing = 10, HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Right, Children = { cancel, confirm } } } };
    }
}

internal sealed class UpdateWindow : Window
{
    public UpdateWindow(AppUpdate update, Version currentVersion)
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
                new TextBlock { Text = $"Installed: {currentVersion.ToString(3)}    Available: {update.Version.ToString(3)}", FontFamily = "Consolas" },
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
