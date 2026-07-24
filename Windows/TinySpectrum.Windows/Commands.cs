using System.Windows.Input;

namespace TinySpectrum.Windows;

public sealed class RelayCommand(Action execute, Func<bool>? canExecute = null) : ICommand
{
    public bool CanExecute(object? parameter) => canExecute?.Invoke() ?? true;
    public void Execute(object? parameter) => execute();
    public event EventHandler? CanExecuteChanged;
    public void RaiseCanExecuteChanged() => CanExecuteChanged?.Invoke(this, EventArgs.Empty);
}

public sealed class AsyncCommand(Func<Task> execute, Func<bool>? canExecute = null) : ICommand
{
    private bool _running;
    public bool CanExecute(object? parameter) => !_running && (canExecute?.Invoke() ?? true);
    public async void Execute(object? parameter)
    {
        if (!CanExecute(parameter)) return;
        _running = true; Raise();
        try { await execute(); } finally { _running = false; Raise(); }
    }
    public event EventHandler? CanExecuteChanged;
    public void Raise() => CanExecuteChanged?.Invoke(this, EventArgs.Empty);
}
