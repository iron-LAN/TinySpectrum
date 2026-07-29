using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Avalonia.Styling;

namespace TinySpectrum.Windows;

public partial class App : Application
{
    private static readonly string ThemeFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TinySpectrum", "theme.txt");

    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
        RequestedThemeVariant = File.Exists(ThemeFile) && File.ReadAllText(ThemeFile).Trim().Equals("light", StringComparison.OrdinalIgnoreCase)
            ? ThemeVariant.Light : ThemeVariant.Dark;
    }

    public static bool IsDark => Current?.RequestedThemeVariant != ThemeVariant.Light;

    public static void ToggleTheme()
    {
        if (Current is null) return;
        Current.RequestedThemeVariant = IsDark ? ThemeVariant.Light : ThemeVariant.Dark;
        Directory.CreateDirectory(Path.GetDirectoryName(ThemeFile)!);
        File.WriteAllText(ThemeFile, IsDark ? "dark" : "light");
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.MainWindow = new MainWindow();
        }

        base.OnFrameworkInitializationCompleted();
    }
}
