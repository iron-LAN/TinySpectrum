using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;

namespace TinySpectrum.Windows;

public partial class MainWindow : Window
{
    private MainViewModel ViewModel => (MainViewModel)DataContext!;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainViewModel();
        Closed += (_, _) => ViewModel.Dispose();
    }

    private void Preset_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: ScanPreset preset }) ViewModel.ApplyPreset(preset);
    }

    private void Visibility_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is CheckBox { Tag: SpectrumScan scan }) ViewModel.ToggleVisibility(scan);
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
}
