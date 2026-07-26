using System.ComponentModel;
using System.Globalization;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media;

namespace TinySpectrum.Windows;

public sealed class SpectrumControl : Control
{
    private MainViewModel? _viewModel;
    private (double Start, double Stop)? _frequencyWindow;
    private (double Start, double Stop)? _dragStartWindow;
    private Point _dragStart;
    private HoverSample? _hover;

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
        _frequencyWindow = null;
        InvalidateVisual();
    }

    private void ViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(MainViewModel.VisibleCount)) _frequencyWindow = null;
        InvalidateVisual();
    }

    public override void Render(DrawingContext context)
    {
        base.Render(context);
        var plot = PlotRect;
        context.DrawRectangle(new SolidColorBrush(Color.Parse("#07131C")), new Pen(new SolidColorBrush(Color.Parse("#224054")), 1), plot);

        var visible = VisibleScans;
        var full = FullRange(visible);
        var range = full is { } fullValue
            ? FrequencyViewport.Clamp(_frequencyWindow ?? fullValue, fullValue)
            : (0d, 1d);
        if (full is not null) _frequencyWindow = range;

        DrawGrid(context, plot);
        DrawAxis(context, plot, range, full is not null);

        if (visible.Length == 0)
        {
            DrawTextCentered(context, "Select a scan or start a new one", plot.Center, 15, "#718292");
            return;
        }

        using (context.PushClip(plot))
        {
            for (var scanIndex = 0; scanIndex < visible.Length; scanIndex++)
            {
                var scan = visible[scanIndex];
                DrawTrace(context, scan.PointsAt(scan.IsContinuous ? _viewModel!.TimelineIndex : null), plot, range,
                    new Pen(new SolidColorBrush(TraceColor(scan)), 1.8));
                if (_viewModel!.PeakHoldEnabled && scan.IsContinuous)
                    DrawTrace(context, scan.PeakHoldAt(_viewModel.TimelineIndex), plot, range, new Pen(Brushes.Red, 1.2));
            }

            if (_hover is { } hover)
            {
                context.DrawLine(new Pen(new SolidColorBrush(Color.Parse("#55FFFFFF")), 1, dashStyle: new DashStyle([3, 3], 0)),
                    new Point(hover.Location.X, plot.Top), new Point(hover.Location.X, plot.Bottom));
                context.DrawEllipse(new SolidColorBrush(hover.Color), null, hover.Location, 4, 4);
            }
        }

        DrawHoverReadout(context, plot);
        DrawText(context, "Scroll to zoom  •  drag to pan", new Point(plot.Right - 178, plot.Top + 8), 10, "#617789");
    }

    protected override void OnPointerWheelChanged(PointerWheelEventArgs e)
    {
        base.OnPointerWheelChanged(e);
        var position = e.GetPosition(this);
        var plot = PlotRect;
        var full = FullRange(VisibleScans);
        if (!plot.Contains(position) || full is null || e.Delta.Y == 0) return;
        var anchor = Math.Clamp((position.X - plot.X) / plot.Width, 0, 1);
        var scale = Math.Exp(-e.Delta.Y * .18);
        _frequencyWindow = FrequencyViewport.Zoom(_frequencyWindow ?? full.Value, full.Value, anchor, scale);
        _hover = null;
        e.Handled = true;
        InvalidateVisual();
    }

    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        var point = e.GetCurrentPoint(this);
        var full = FullRange(VisibleScans);
        if (!point.Properties.IsLeftButtonPressed || !PlotRect.Contains(point.Position) || full is null) return;
        var current = FrequencyViewport.Clamp(_frequencyWindow ?? full.Value, full.Value);
        if (current == full.Value) return;
        _dragStart = point.Position;
        _dragStartWindow = current;
        e.Pointer.Capture(this);
        e.Handled = true;
    }

    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);
        var position = e.GetPosition(this);
        var full = FullRange(VisibleScans);
        if (_dragStartWindow is { } start && full is { } fullValue)
        {
            _frequencyWindow = FrequencyViewport.Pan(start, fullValue, (position.X - _dragStart.X) / PlotRect.Width);
            _hover = null;
            e.Handled = true;
        }
        else
        {
            _hover = NearestSample(position);
        }
        InvalidateVisual();
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        if (_dragStartWindow is null) return;
        _dragStartWindow = null;
        e.Pointer.Capture(null);
        e.Handled = true;
    }

    protected override void OnPointerExited(PointerEventArgs e)
    {
        base.OnPointerExited(e);
        if (_dragStartWindow is null) _hover = null;
        InvalidateVisual();
    }

    private Rect PlotRect => new(68, 42, Math.Max(1, Bounds.Width - 88), Math.Max(1, Bounds.Height - 84));
    private SpectrumScan[] VisibleScans => _viewModel?.Scans.Where(scan => scan.IsVisible).ToArray() ?? [];

    private (double Start, double Stop)? FullRange(IReadOnlyList<SpectrumScan> visible)
    {
        var points = visible.SelectMany(scan => scan.PointsAt(scan.IsContinuous ? _viewModel!.TimelineIndex : null)).ToArray();
        if (points.Length == 0) return null;
        var start = points.Min(point => point.Frequency);
        var stop = points.Max(point => point.Frequency);
        return stop > start ? (start, stop) : (start, start + 1);
    }

    private HoverSample? NearestSample(Point cursor)
    {
        var plot = PlotRect;
        var visible = VisibleScans;
        var full = FullRange(visible);
        if (!plot.Contains(cursor) || full is null) return null;
        var range = FrequencyViewport.Clamp(_frequencyWindow ?? full.Value, full.Value);
        HoverSample? nearest = null;
        var bestDistance = double.MaxValue;
        for (var scanIndex = 0; scanIndex < visible.Length; scanIndex++)
        {
            foreach (var point in visible[scanIndex].PointsAt(visible[scanIndex].IsContinuous ? _viewModel!.TimelineIndex : null)
                         .Where(point => point.Frequency >= range.Start && point.Frequency <= range.Stop))
            {
                var location = Map(point, plot, range);
                var distance = Math.Sqrt(Math.Pow(location.X - cursor.X, 2) + Math.Pow(location.Y - cursor.Y, 2));
                if (distance >= bestDistance) continue;
                bestDistance = distance;
                nearest = new(point, TraceColor(visible[scanIndex]), location);
            }
        }
        return nearest;
    }

    private Color TraceColor(SpectrumScan scan)
    {
        var index = _viewModel?.Scans.IndexOf(scan) ?? 0;
        return Color.Parse(ScanPalette.At(index));
    }

    private static void DrawTrace(DrawingContext context, IReadOnlyList<ScanPoint> points, Rect plot,
        (double Start, double Stop) range, Pen pen)
    {
        if (points.Count < 2) return;
        var geometry = new StreamGeometry();
        using (var drawing = geometry.Open())
        {
            drawing.BeginFigure(Map(points[0], plot, range), false);
            for (var index = 1; index < points.Count; index++) drawing.LineTo(Map(points[index], plot, range));
        }
        context.DrawGeometry(null, pen, geometry);
    }

    private static Point Map(ScanPoint point, Rect plot, (double Start, double Stop) range)
    {
        var x = plot.X + (point.Frequency - range.Start) / (range.Stop - range.Start) * plot.Width;
        var y = plot.Y + Math.Clamp((-20 - point.Level) / 100, 0, 1) * plot.Height;
        return new(x, y);
    }

    private static void DrawGrid(DrawingContext context, Rect plot)
    {
        var pen = new Pen(new SolidColorBrush(Color.Parse("#213643")), 1);
        for (var index = 0; index <= 10; index++)
        {
            var x = plot.X + plot.Width * index / 10;
            context.DrawLine(pen, new(x, plot.Y), new(x, plot.Bottom));
        }
        for (var index = 0; index <= 5; index++)
        {
            var y = plot.Y + plot.Height * index / 5;
            context.DrawLine(pen, new(plot.X, y), new(plot.Right, y));
            DrawText(context, $"{-20 - index * 20}", new(12, y - 8), 11, "#8497A6");
        }
        DrawText(context, "dBm", new(12, plot.Top - 22), 11, "#8497A6");
    }

    private static void DrawAxis(DrawingContext context, Rect plot, (double Start, double Stop) range, bool hasData)
    {
        if (!hasData) return;
        var step = FrequencyAxis.TickStep(range.Start, range.Stop, plot.Width);
        var values = FrequencyAxis.LabelValues(range.Start, range.Stop, plot.Width, step);
        for (var index = 0; index < values.Count; index++)
        {
            var value = values[index];
            var x = plot.X + (value - range.Start) / (range.Stop - range.Start) * plot.Width;
            var text = FrequencyAxis.Label(value);
            var alignment = index == 0 ? TextAlignment.Left : index == values.Count - 1 ? TextAlignment.Right : TextAlignment.Center;
            DrawTextAligned(context, text, new(x, plot.Bottom + 12), 11, "#8497A6", alignment);
        }
    }

    private void DrawHoverReadout(DrawingContext context, Rect plot)
    {
        if (_hover is not { } hover) return;
        var readout = new Rect(plot.Center.X - 142, plot.Top + 5, 284, 30);
        context.DrawRectangle(new SolidColorBrush(Color.Parse("#DD17232D")), new Pen(new SolidColorBrush(hover.Color), 1),
            new RoundedRect(readout, 15));
        var icon = new StreamGeometry();
        using (var drawing = icon.Open())
        {
            var centerY = readout.Center.Y;
            drawing.BeginFigure(new(readout.X + 14, centerY), false);
            drawing.LineTo(new(readout.X + 20, centerY));
            drawing.LineTo(new(readout.X + 24, centerY - 5));
            drawing.LineTo(new(readout.X + 29, centerY + 6));
            drawing.LineTo(new(readout.X + 34, centerY - 7));
            drawing.LineTo(new(readout.X + 40, centerY));
        }
        context.DrawGeometry(null, new Pen(new SolidColorBrush(Color.Parse("#19D9FF")), 1.6), icon);
        var frequency = string.Create(CultureInfo.InvariantCulture, $"{hover.Point.Frequency / 1e6:F3} MHz");
        var level = string.Create(CultureInfo.InvariantCulture, $"{hover.Point.Level:F2} dBm");
        DrawText(context, frequency, new(readout.X + 50, readout.Y + 7), 12, "#F4FAFF");
        DrawText(context, level, new(readout.X + 184, readout.Y + 7), 12, "#F4FAFF");
    }

    private static void DrawText(DrawingContext context, string text, Point point, double size, string color) =>
        context.DrawText(Format(text, size, color), point);

    private static void DrawTextCentered(DrawingContext context, string text, Point center, double size, string color)
    {
        var formatted = Format(text, size, color);
        context.DrawText(formatted, new(center.X - formatted.Width / 2, center.Y - formatted.Height / 2));
    }

    private static void DrawTextAligned(DrawingContext context, string text, Point point, double size, string color, TextAlignment alignment)
    {
        var formatted = Format(text, size, color);
        var x = alignment switch { TextAlignment.Right => point.X - formatted.Width, TextAlignment.Center => point.X - formatted.Width / 2, _ => point.X };
        context.DrawText(formatted, new(x, point.Y));
    }

    private static FormattedText Format(string text, double size, string color) =>
        new(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, new Typeface("Inter"), size,
            new SolidColorBrush(Color.Parse(color)));

    private sealed record HoverSample(ScanPoint Point, Color Color, Point Location);
}

public sealed class CountdownControl : Control
{
    public static readonly StyledProperty<double?> ProgressProperty =
        AvaloniaProperty.Register<CountdownControl, double?>(nameof(Progress));
    public static readonly StyledProperty<string> RemainingTextProperty =
        AvaloniaProperty.Register<CountdownControl, string>(nameof(RemainingText), "");

    static CountdownControl()
    {
        AffectsRender<CountdownControl>(ProgressProperty, RemainingTextProperty);
    }

    public double? Progress { get => GetValue(ProgressProperty); set => SetValue(ProgressProperty, value); }
    public string RemainingText { get => GetValue(RemainingTextProperty); set => SetValue(RemainingTextProperty, value); }

    public override void Render(DrawingContext context)
    {
        base.Render(context);
        if (Progress is not { } progress) return;
        var center = Bounds.Center;
        var radius = Math.Max(4, Math.Min(Bounds.Width, Bounds.Height) / 2 - 4);
        context.DrawEllipse(null, new Pen(new SolidColorBrush(Color.Parse("#39434F")), 3), center, radius, radius);
        var start = -Math.PI / 2;
        var end = start + Math.PI * 2 * Math.Clamp(progress, 0, .9999);
        var geometry = new StreamGeometry();
        using (var drawing = geometry.Open())
        {
            drawing.BeginFigure(new(center.X + radius * Math.Cos(start), center.Y + radius * Math.Sin(start)), false);
            drawing.ArcTo(new(center.X + radius * Math.Cos(end), center.Y + radius * Math.Sin(end)),
                new(radius, radius), 0, progress > .5, SweepDirection.Clockwise);
        }
        context.DrawGeometry(null, new Pen(new SolidColorBrush(Color.Parse("#A855F7")), 3), geometry);
        var formatted = new FormattedText(RemainingText, CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
            new Typeface("Inter", FontStyle.Normal, FontWeight.Bold), 9, Brushes.White);
        context.DrawText(formatted, new(center.X - formatted.Width / 2, center.Y - formatted.Height / 2));
    }
}
