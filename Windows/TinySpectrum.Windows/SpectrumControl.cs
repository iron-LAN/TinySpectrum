using System.ComponentModel;
using System.Globalization;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;

namespace TinySpectrum.Windows;

public sealed class SpectrumControl : Control
{
    private MainViewModel? _viewModel;
    private static readonly Color[] TraceColors =
    [Color.Parse("#18D8FF"), Color.Parse("#FF8B22"), Color.Parse("#A855F7"), Color.Parse("#34D399"), Color.Parse("#F43F8A")];

    public SpectrumControl()
    {
        DataContextChanged += (_, _) => AttachViewModel();
        ClipToBounds = true;
    }

    private void AttachViewModel()
    {
        if (_viewModel is not null) _viewModel.PropertyChanged -= ViewModelChanged;
        _viewModel = DataContext as MainViewModel;
        if (_viewModel is not null) _viewModel.PropertyChanged += ViewModelChanged;
        InvalidateVisual();
    }

    private void ViewModelChanged(object? sender, PropertyChangedEventArgs e) => InvalidateVisual();

    public override void Render(DrawingContext context)
    {
        base.Render(context);
        var bounds = Bounds;
        context.DrawRectangle(Brushes.Transparent, null, bounds);
        var plot = new Rect(58, 22, Math.Max(1, bounds.Width - 78), Math.Max(1, bounds.Height - 62));
        var grid = new Pen(new SolidColorBrush(Color.Parse("#263542")), 1);
        for (var i = 0; i <= 10; i++)
        {
            var x = plot.X + plot.Width * i / 10;
            context.DrawLine(grid, new Point(x, plot.Y), new Point(x, plot.Bottom));
        }
        for (var i = 0; i <= 5; i++)
        {
            var y = plot.Y + plot.Height * i / 5;
            context.DrawLine(grid, new Point(plot.X, y), new Point(plot.Right, y));
            DrawText(context, $"{-20 - i * 20}", new Point(8, y - 8), 11, "#8494A3");
        }

        var visible = _viewModel?.Scans.Where(x => x.IsVisible).ToArray() ?? [];
        var points = visible.SelectMany(scan => scan.PointsAt(scan.IsContinuous ? _viewModel!.TimelineIndex : null)).ToArray();
        if (points.Length == 0)
        {
            DrawText(context, "Connect a tinySA or start Demo mode", new Point(plot.Center.X - 135, plot.Center.Y - 10), 15, "#718292");
            return;
        }
        var minFrequency = points.Min(x => x.Frequency);
        var maxFrequency = points.Max(x => x.Frequency);
        if (maxFrequency <= minFrequency) maxFrequency = minFrequency + 1;

        for (var scanIndex = 0; scanIndex < visible.Length; scanIndex++)
        {
            var scan = visible[scanIndex];
            DrawTrace(context, scan.PointsAt(scan.IsContinuous ? _viewModel!.TimelineIndex : null), plot, minFrequency, maxFrequency,
                new Pen(new SolidColorBrush(TraceColors[scanIndex % TraceColors.Length]), 1.7));
            if (_viewModel!.PeakHoldEnabled && scan.IsContinuous)
                DrawTrace(context, scan.PeakHoldAt(_viewModel.TimelineIndex), plot, minFrequency, maxFrequency, new Pen(Brushes.Red, 1.25));
        }
        DrawText(context, FrequencyText.Short(minFrequency), new Point(plot.X, plot.Bottom + 9), 11, "#8494A3");
        var endLabel = FrequencyText.Short(maxFrequency);
        DrawText(context, endLabel, new Point(plot.Right - 70, plot.Bottom + 9), 11, "#8494A3");
        DrawText(context, "dBm", new Point(8, 2), 11, "#8494A3");
    }

    private static void DrawTrace(DrawingContext context, IReadOnlyList<ScanPoint> points, Rect plot, double minFrequency, double maxFrequency, Pen pen)
    {
        if (points.Count < 2) return;
        var geometry = new StreamGeometry();
        using (var drawing = geometry.Open())
        {
            var first = Map(points[0]);
            drawing.BeginFigure(first, false);
            for (var i = 1; i < points.Count; i++) drawing.LineTo(Map(points[i]));
        }
        context.DrawGeometry(null, pen, geometry);
        return;

        Point Map(ScanPoint point)
        {
            var x = plot.X + (point.Frequency - minFrequency) / (maxFrequency - minFrequency) * plot.Width;
            var y = plot.Y + Math.Clamp((-20 - point.Level) / 100, 0, 1) * plot.Height;
            return new Point(x, y);
        }
    }

    private static void DrawText(DrawingContext context, string text, Point point, double size, string color)
    {
        var formatted = new FormattedText(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
            new Typeface("Inter"), size, new SolidColorBrush(Color.Parse(color)));
        context.DrawText(formatted, point);
    }
}

public sealed class CountdownControl : Control
{
    private MainViewModel? _viewModel;
    public CountdownControl()
    {
        DataContextChanged += (_, _) =>
        {
            if (_viewModel is not null) _viewModel.PropertyChanged -= Changed;
            _viewModel = DataContext as MainViewModel;
            if (_viewModel is not null) _viewModel.PropertyChanged += Changed;
        };
    }
    private void Changed(object? sender, PropertyChangedEventArgs e) => InvalidateVisual();
    public override void Render(DrawingContext context)
    {
        base.Render(context);
        if (_viewModel?.IntervalProgress is not { } progress) return;
        var center = Bounds.Center;
        var radius = Math.Max(4, Math.Min(Bounds.Width, Bounds.Height) / 2 - 4);
        context.DrawEllipse(null, new Pen(new SolidColorBrush(Color.Parse("#39434F")), 3), center, radius, radius);
        var start = -Math.PI / 2;
        var end = start + Math.PI * 2 * Math.Clamp(progress, 0, .9999);
        var geometry = new StreamGeometry();
        using (var drawing = geometry.Open())
        {
            drawing.BeginFigure(new Point(center.X + radius * Math.Cos(start), center.Y + radius * Math.Sin(start)), false);
            drawing.ArcTo(new Point(center.X + radius * Math.Cos(end), center.Y + radius * Math.Sin(end)),
                new Size(radius, radius), 0, progress > .5, SweepDirection.Clockwise);
        }
        context.DrawGeometry(null, new Pen(new SolidColorBrush(Color.Parse("#A855F7")), 3), geometry);
        var text = _viewModel.CountdownText;
        var formatted = new FormattedText(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
            new Typeface("Inter", FontStyle.Normal, FontWeight.Bold), 9, Brushes.White);
        context.DrawText(formatted, new Point(center.X - formatted.Width / 2, center.Y - formatted.Height / 2));
    }
}
