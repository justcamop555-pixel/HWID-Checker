using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

namespace HwidDesktop;

public partial class MainWindow : Window
{
    public ObservableCollection<ScanRow> ScanRows { get; } = [];
    private readonly string[] _args;
    private readonly HashSet<string> _additionalFolders = new(StringComparer.OrdinalIgnoreCase);
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly Stopwatch _scanClock = new();
    private EngineClient? _engine;
    private DesktopUpdater? _updater;
    private bool _restartForUpdate;
    private static readonly string[] ScanSectionNames =
    [
        "System identity", "System hardware", "Motherboard", "BIOS", "Chassis", "CPU", "Memory modules",
        "Physical disks", "Storage identifiers", "Volumes", "Disk partitions", "Graphics adapters",
        "Monitors", "Network adapters", "Battery", "Windows", "Windows Machine GUID", "PnP hardware IDs", "All-known device catalog"
    ];
    private static readonly Dictionary<string, string> MidnightColors = new(StringComparer.Ordinal)
    {
        ["CanvasBrush"] = "#0D1521", ["SidebarBrush"] = "#101B29", ["PanelBrush"] = "#152131",
        ["BorderBrush"] = "#304258", ["TextBrush"] = "#EEF5FA", ["MutedBrush"] = "#A7B9CC",
        ["AccentBrush"] = "#66E1CE", ["WarningBrush"] = "#F3C785", ["NavActiveBrush"] = "#214642",
        ["StatusBrush"] = "#173235", ["StatusBorderBrush"] = "#36535D", ["ControlBrush"] = "#1C2B3F",
        ["ControlBorderBrush"] = "#405673", ["ControlHoverBrush"] = "#2B4055", ["DisabledControlBrush"] = "#202B38",
        ["DisabledTextBrush"] = "#9AA9BA", ["FocusBrush"] = "#BAF6E9", ["PrimaryForegroundBrush"] = "#082A2A",
        ["ScrollThumbBrush"] = "#3D526C", ["ScrollThumbHoverBrush"] = "#64809E", ["ScrollTrackBrush"] = "#101A2A",
        ["RowAlternateBrush"] = "#142032", ["ColumnHeaderBrush"] = "#18263A", ["SelectionBrush"] = "#214C49",
        ["SelectionTextBrush"] = "#F1FFFC", ["ListSelectedBrush"] = "#21423F", ["ListHoverBrush"] = "#213349"
    };
    private static readonly Dictionary<string, string> DaylightColors = new(StringComparer.Ordinal)
    {
        ["CanvasBrush"] = "#EEF2F7", ["SidebarBrush"] = "#F8FAFC", ["PanelBrush"] = "#FFFFFF",
        ["BorderBrush"] = "#C6D2DE", ["TextBrush"] = "#17222E", ["MutedBrush"] = "#5B6B7C",
        ["AccentBrush"] = "#0F766E", ["WarningBrush"] = "#8A5A00", ["NavActiveBrush"] = "#D7EEE9",
        ["StatusBrush"] = "#E1F1ED", ["StatusBorderBrush"] = "#A7CFC6", ["ControlBrush"] = "#FFFFFF",
        ["ControlBorderBrush"] = "#B9C7D4", ["ControlHoverBrush"] = "#E9F0F6", ["DisabledControlBrush"] = "#E7ECF1",
        ["DisabledTextBrush"] = "#97A4B1", ["FocusBrush"] = "#0F766E", ["PrimaryForegroundBrush"] = "#FFFFFF",
        ["ScrollThumbBrush"] = "#AEBFCF", ["ScrollThumbHoverBrush"] = "#7E93A8", ["ScrollTrackBrush"] = "#E3EAF1",
        ["RowAlternateBrush"] = "#F4F7FA", ["ColumnHeaderBrush"] = "#E8EEF4", ["SelectionBrush"] = "#CDEBE5",
        ["SelectionTextBrush"] = "#0B3B34", ["ListSelectedBrush"] = "#CDEBE5", ["ListHoverBrush"] = "#E9F0F6"
    };
    private DesktopSnapshot? _snapshot;
    private CancellationTokenSource? _operationCancellation;
    private bool _busy, _initialized, _closing, _closeRequested, _refreshAgain;
    private Task? _snapshotRefreshTask;
    private TaskCompletionSource<bool>? _operationFinished;
    private string _page = "Overview", _operation = "", _lastSaveFolder = "";
    private string? _rememberedBat;
    private bool _darkTheme = true;
    private bool _restarting;
    private string _pendingPage = "";
    private readonly Dictionary<FrameworkElement, AnimationClock> _fadeClocks = [];
    private Action? _closeCompletion;
    private bool _closeCompletionQueued;
    private IReadOnlyList<ChangeRow>? _lastComparisonRows;
    private string _lastComparisonSummary = "", _lastComparisonNotes = "", _lastComparisonBaseline = "", _lastComparisonCurrent = "";
    private bool _comparisonHasFields, _comparisonHasGaps, _comparisonSameFile;
    private int _scanGeneration, _scanCompletedStages, _scanTotalStages = ScanSectionNames.Length;
    private bool IsVerification => _args.Any(argument => argument.Split('=', 2)[0].ToLowerInvariant() is
        "--fixture" or "--render" or "--scan-test" or "--workflow-test" or "--ui-test" or "--readability-test");
    private int _ticks, _responsiveTicks;
    private string SettingsPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HWID Checker", "Desktop", "settings.json");
    private string DefaultReportsFolder => Path.Combine(Path.GetDirectoryName(_engine?.BatPath) ?? AppContext.BaseDirectory, "HWID-Reports");
    private string LocalReportsFolder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HWID Checker", "HWID-Reports");
    private string? VerificationSharedSettingsPath =>
        IsVerification && Argument("--shared-settings") is { } path && !string.IsNullOrWhiteSpace(path) ? path : null;

    public MainWindow(string[] args)
    {
        _args = args;
        if (!IsVerification) LoadPreferences();
        InitializeComponent();
        var work = SystemParameters.WorkArea;
        var availableWidth = Math.Max(1, work.Width - 16);
        var availableHeight = Math.Max(1, work.Height - 16);
        MinWidth = Math.Min(MinWidth, availableWidth);
        MinHeight = Math.Min(MinHeight, availableHeight);
        Width = Math.Min(Width, availableWidth);
        Height = Math.Min(Height, availableHeight);
        if (Argument("--size") is { } size)
        {
            var dimensions = size.Split('x');
            if (dimensions.Length == 2 && double.TryParse(dimensions[0], out var width) && double.TryParse(dimensions[1], out var height)) { Width = width; Height = height; }
        }
        Dashboard.SizeChanged += (_, _) => FitLayout();
        DataContext = this;
        SideVersionText.Text = "Desktop " + DesktopUpdater.CurrentVersion;
        _initialized = true;
        UpdateEmptyStates();
        ApplyTheme(_darkTheme);
        FitLayout();
        _timer.Tick += async (_, _) =>
        {
            _responsiveTicks++;
            if (_busy && _operation == "Scan")
                ScanElapsedText.Text = $"{_scanCompletedStages} of {_scanTotalStages} checks finished  ·  {_scanClock.Elapsed:mm\\:ss}";
            if (++_ticks % 15 == 0 && _page == "Snapshots" && !_busy && !IsVerification) await RefreshSnapshotsAsync();
        };
        _timer.Start();
        InputBindings.Add(new KeyBinding(new UiCommand(async () => await RunScanAsync(), () => !_busy && _engine != null), Key.R, ModifierKeys.Control));
        InputBindings.Add(new KeyBinding(new UiCommand(async () => await SaveSnapshotAsync(), () => !_busy && _snapshot != null), Key.S, ModifierKeys.Control));
        InputBindings.Add(new KeyBinding(new UiCommand(FocusSearch, () => true), Key.F, ModifierKeys.Control));
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        Navigate("Overview");
        if (!IsVerification && _pendingPage.Length > 0) Navigate(_pendingPage);
        ConnectEngine(FindEngine());
        if (Argument("--render") == null || Argument("--workflow-test") != null)
            await RefreshSnapshotsAsync();
        else
        {
            SnapshotCountText.Text = "No saved snapshots in this preview.";
            ShowSnapshotFolders(ReadSharedLibrary());
        }
        var fixture = Argument("--fixture");
        if (fixture != null)
        {
            using var doc = JsonDocument.Parse(await File.ReadAllTextAsync(fixture));
            var data = doc.RootElement.Get("data");
            ApplySnapshot(new DesktopSnapshot(data.ValueKind == JsonValueKind.Object ? data : doc.RootElement));
            ShowStatus("Snapshot loaded", "Synthetic fixture for desktop verification.");
        }
        var workflow = Argument("--workflow-test");
        if (workflow != null) await VerifyWorkflowAsync(workflow);
        if (Argument("--ui-test") is { } uiTest) await VerifyUiRegressionAsync(uiTest);
        if (Argument("--readability-test") is { } readabilityTest) await VerifyReadabilityAsync(readabilityTest);
        var scanTest = Argument("--scan-test");
        if (scanTest != null)
        {
            var success = await RunScanAsync();
            await WriteTestResultAsync(scanTest, success);
            Close();
            return;
        }
        var render = Argument("--render");
        if (render != null)
        {
            var page = Argument("--page");
            if (page != null) Navigate(page);
            var stress = _args.Contains("--layout-stress", StringComparer.OrdinalIgnoreCase);
            if (stress) PrepareLayoutStress();
            await Task.Delay(200);
            await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            UpdateLayout();
            if (stress) VerifyLayoutStress();
            var surface = (FrameworkElement)Content;
            var image = new RenderTargetBitmap((int)Math.Ceiling(surface.ActualWidth), (int)Math.Ceiling(surface.ActualHeight), 96, 96, PixelFormats.Pbgra32);
            image.Render(surface);
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(image));
            using var stream = File.Create(render); encoder.Save(stream);
            var verify = Argument("--verify");
            if (verify != null) await WriteTestResultAsync(verify, true);
            Close();
            return;
        }
        if (!IsVerification)
        {
            // An update can complete on disk while an older window is still open;
            // say so plainly instead of looking like a failed update check.
            try
            {
                var disk = DesktopUpdater.ReadInstalledPackageVersion(Process.GetCurrentProcess().MainModule!.FileName!);
                if (disk != null && DesktopUpdater.IsNewerPackageVersion(disk, Version.Parse(DesktopUpdater.CurrentVersion)))
                    ShowStatus("Update already installed", "The files on disk are desktop v" + disk.ToString(3) +
                        ", newer than this running window (v" + DesktopUpdater.CurrentVersion + "). Close and reopen the app to load it.", true);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException or FormatException) { }
            _updater = new DesktopUpdater(AppContext.BaseDirectory);
            _updater.Changed += (_, _) => UpdateUpdateButton();
            UpdateUpdateButton();
            await _updater.PrepareAutomaticallyAsync();
        }
    }

    private string? Argument(string name)
    {
        for (var i = 0; i < _args.Length; i++)
        {
            if (_args[i].Equals(name, StringComparison.OrdinalIgnoreCase) && i + 1 < _args.Length) return _args[i + 1];
            if (_args[i].StartsWith(name + "=", StringComparison.OrdinalIgnoreCase)) return _args[i][(name.Length + 1)..];
        }
        return null;
    }
    private void FitLayout()
    {
        if (!_initialized) return;
        var width = Dashboard.ActualWidth > 0 ? Dashboard.ActualWidth : Width;
        var height = Dashboard.ActualHeight > 0 ? Dashboard.ActualHeight : Height;
        var sidebar = width < 900 ? 148 : width < 1100 ? 184 : 212;
        var inset = width < 900 ? 12 : width < 1100 ? 18 : 24;
        var shortWindow = height < 600;
        var workspace = width - sidebar - 2 * inset;
        var stackedHeader = workspace < 675;
        var compactHardware = workspace < 655;

        SidebarColumn.Width = new GridLength(sidebar);
        BrandText.Text = width < 900 ? "HWID" : "HWID Checker";
        foreach (var button in new[] { OverviewNav, IdentifiersNav, HardwareNav, ReviewNav, SnapshotsNav, CompareNav })
        {
            button.Padding = shortWindow ? new Thickness(9, 8, 9, 8) : new Thickness(12, 10, 12, 10);
            button.Margin = shortWindow ? new Thickness(0, 1, 0, 1) : new Thickness(0, 2, 0, 2);
        }
        Workspace.Margin = new Thickness(inset, shortWindow ? 10 : 20, inset, shortWindow ? 8 : 12);
        PageTitle.FontSize = stackedHeader ? 24 : 28;
        PageSubtitle.Visibility = shortWindow ? Visibility.Collapsed : Visibility.Visible;
        HeaderPanel.Margin = new Thickness(0, 0, 0, shortWindow ? 6 : 12);
        StatusPanel.Padding = shortWindow ? new Thickness(10, 6, 10, 6) : new Thickness(11, 8, 11, 8);
        StatusPanel.Margin = new Thickness(0, 0, 0, shortWindow ? 6 : 13);
        FooterPanel.Margin = new Thickness(0, shortWindow ? 4 : 9, 0, 0);
        foreach (var button in HeaderActions.Children.OfType<Button>())
        {
            button.Padding = shortWindow ? new Thickness(9, 5, 9, 5) : new Thickness(15, 10, 15, 10);
            button.FontSize = shortWindow ? 13 : 14;
        }
        HeaderText.Margin = stackedHeader ? new Thickness(0) : new Thickness(0, 0, 14, 0);
        Grid.SetColumnSpan(HeaderText, stackedHeader ? 2 : 1);
        Grid.SetRow(HeaderActions, stackedHeader ? 1 : 0);
        Grid.SetColumn(HeaderActions, stackedHeader ? 0 : 1);
        Grid.SetColumnSpan(HeaderActions, stackedHeader ? 2 : 1);
        HeaderActions.Margin = stackedHeader ? new Thickness(0, shortWindow ? 6 : 8, 0, 0) : new Thickness(0);
        var stackedComparison = workspace < 735;
        Grid.SetRow(CompareActions, stackedComparison ? 1 : 0);
        Grid.SetColumn(CompareActions, stackedComparison ? 0 : 1);
        Grid.SetColumnSpan(CompareActions, stackedComparison ? 2 : 1);
        Grid.SetColumnSpan(CompareHeaderText, stackedComparison ? 2 : 1);
        CompareActions.HorizontalAlignment = stackedComparison ? HorizontalAlignment.Left : HorizontalAlignment.Right;
        CompareActions.Margin = stackedComparison ? new Thickness(0, 6, 0, 0) : new Thickness(0);
        foreach (var button in CompareActions.Children.OfType<Button>())
            button.Padding = shortWindow ? new Thickness(8, 5, 8, 5) : new Thickness(15, 10, 15, 10);
        MetricsGrid.Columns = workspace < 625 ? 2 : 4;
        var stackedComputer = workspace < 625;
        OverviewComputerColumn.Width = new GridLength(1, GridUnitType.Star);
        OverviewCpuColumn.Width = new GridLength(stackedComputer ? 0 : 1, GridUnitType.Star);
        OverviewWindowsColumn.Width = new GridLength(stackedComputer ? 0 : 1, GridUnitType.Star);
        Grid.SetRow(CpuSummary, stackedComputer ? 1 : 0);
        Grid.SetRow(WindowsSummary, stackedComputer ? 2 : 0);
        Grid.SetColumn(CpuSummary, stackedComputer ? 0 : 1);
        Grid.SetColumn(WindowsSummary, stackedComputer ? 0 : 2);
        ComputerSummary.Margin = stackedComputer ? new Thickness(0, 0, 0, 10) : new Thickness(0, 0, 14, 0);
        CpuSummary.Margin = stackedComputer ? new Thickness(0, 0, 0, 10) : new Thickness(0, 0, 14, 0);
        HardwareSectionsColumn.Width = new GridLength(compactHardware ? 0 : 210);
        HardwareSectionsPanel.Visibility = compactHardware ? Visibility.Collapsed : Visibility.Visible;
        HardwareSectionPicker.Visibility = compactHardware ? Visibility.Visible : Visibility.Collapsed;
        HardwareSectionTitle.Visibility = compactHardware ? Visibility.Collapsed : Visibility.Visible;
        Grid.SetColumn(HardwareRecord, compactHardware ? 1 : 0);
        Grid.SetColumnSpan(HardwareRecord, compactHardware ? 1 : 2);
        HardwareSearch.Padding = shortWindow ? new Thickness(8, 5, 8, 5) : new Thickness(12, 9, 12, 9);
        HardwareSearchHost.Margin = new Thickness(0, 0, 0, shortWindow ? 4 : 8);
        HardwareDetailRow.MinHeight = shortWindow ? 52 : 70;
        CompareDetailRow.MinHeight = CompareDetailPanel.Visibility == Visibility.Visible ? shortWindow ? 66 : 76 : 0;
        foreach (var picker in new[] { HardwareSectionPicker, HardwareRecord })
        {
            picker.MinHeight = shortWindow ? 30 : 38;
            picker.Padding = shortWindow ? new Thickness(8, 5, 27, 5) : new Thickness(12, 8, 33, 8);
        }
        CopyHardwareButton.Padding = shortWindow ? new Thickness(9, 5, 9, 5) : new Thickness(15, 10, 15, 10);
        foreach (var table in new[] { ScanGrid, IdentifiersGrid, HardwareFields, ReviewGrid, SnapshotsGrid, CompareGrid })
        {
            table.RowHeight = shortWindow ? 34 : 42;
            table.ColumnHeaderHeight = shortWindow ? 36 : 40;
        }
    }
    private string? FindEngine()
    {
        if (Argument("--engine") is { } explicitPath) return explicitPath;
        if (File.Exists(_rememberedBat)) return _rememberedBat;
        var adjacent = Path.Combine(AppContext.BaseDirectory, "hwid.bat");
        if (File.Exists(adjacent)) return adjacent;
        var parent = Directory.GetParent(AppContext.BaseDirectory)?.FullName;
        if (parent != null && File.Exists(Path.Combine(parent, "hwid.bat"))) return Path.Combine(parent, "hwid.bat");
        return null;
    }
    private void LoadPreferences(string? source = null)
    {
        try
        {
            var path = source ?? SettingsPath;
            if (!File.Exists(path) || new FileInfo(path).Length > 262144) return;
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            var preferences = document.RootElement;
            _rememberedBat = preferences.Text("batPath");
            if (preferences.Get("darkTheme").ValueKind is JsonValueKind.True or JsonValueKind.False) _darkTheme = preferences.Get("darkTheme").ValueKind == JsonValueKind.True;
            var savedPage = preferences.Text("lastPage");
            if (savedPage.Length > 0) _pendingPage = savedPage;
            var lastFolder = preferences.Text("lastSaveFolder");
            if (Path.IsPathFullyQualified(lastFolder)) _lastSaveFolder = Path.GetFullPath(lastFolder);
            foreach (var folder in preferences.Get("snapshotFolders").Rows().Select(x => x.Text()))
                if (Path.IsPathFullyQualified(folder)) _additionalFolders.Add(Path.GetFullPath(folder));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException or ArgumentException) { }
    }
    private async Task<bool> RememberPreferencesAsync(string? destination = null)
    {
        if (IsVerification && destination == null) return true;
        var path = destination ?? SettingsPath;
        var temporary = path + ".pending-" + Guid.NewGuid().ToString("N");
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var preferences = JsonSerializer.Serialize(new { batPath = _engine?.BatPath, lastSaveFolder = _lastSaveFolder, snapshotFolders = _additionalFolders.ToArray(), darkTheme = _darkTheme, lastPage = _page });
            await File.WriteAllTextAsync(temporary, preferences);
            File.Move(temporary, path, true);
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { return false; }
        finally { try { if (File.Exists(temporary)) File.Delete(temporary); } catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { } }
    }
    // Synchronous twin used on close paths: an async save started right before
    // shutdown can be discarded with the process, losing the last page/theme.
    private bool RememberPreferencesNow(string? destination = null)
    {
        if (IsVerification && destination == null) return true;
        var path = destination ?? SettingsPath;
        var temporary = path + ".pending-" + Guid.NewGuid().ToString("N");
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var preferences = JsonSerializer.Serialize(new { batPath = _engine?.BatPath, lastSaveFolder = _lastSaveFolder, snapshotFolders = _additionalFolders.ToArray(), darkTheme = _darkTheme, lastPage = _page });
            File.WriteAllText(temporary, preferences);
            File.Move(temporary, path, true);
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { return false; }
        finally { try { if (File.Exists(temporary)) File.Delete(temporary); } catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { } }
    }
    private void ConnectEngine(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            EngineConnectionText.Text = "BAT connection needed";
            EngineVersionText.Text = "Choose your hwid.bat file";
            ScanButton.IsEnabled = false;
            _engine?.Dispose();
            _engine = null;
            UpdateButtons();
            ShowStatus("Connect your checker", "Keep the EXE beside hwid.bat, or use Connect BAT to select the scanner.", true);
            return;
        }
        try
        {
            _engine?.Dispose();
            _engine = new EngineClient(Path.GetFullPath(path));
            EngineConnectionText.Text = "BAT connected";
            EngineConnectionText.ToolTip = _engine.BatPath;
            var version = Regex.Match(File.ReadAllText(path), @"Version\s*=\s*'([0-9.]+)'");
            EngineVersionText.Text = version.Success ? "Scanner v" + version.Groups[1].Value : "Existing PowerShell scanner";
            FooterText.Text = "Connected to " + Path.GetFileName(path) + "  ·  Windows-reported inventory";
            FooterText.ToolTip = _engine.BatPath;
            UpdateButtons();
            ShowStatus("Ready to scan", "Choose Scan this PC to read hardware information and the identifiers Windows supplies.");
        }
        catch (Exception ex) { _engine = null; UpdateButtons(); ShowError("Could not connect the BAT", ex); }
    }
    private void ApplyTheme(bool dark)
    {
        var palette = dark ? MidnightColors : DaylightColors;
        var resources = Application.Current.Resources;
        foreach (var pair in palette)
        {
            var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(pair.Value));
            brush.Freeze();
            resources[pair.Key] = brush;
        }
        ThemeButton.Content = dark ? "Theme: Midnight" : "Theme: Daylight";
    }

    private async void OnToggleTheme(object sender, RoutedEventArgs e)
    {
        if (IsVerification) return;
        _darkTheme = !_darkTheme;
        ApplyTheme(_darkTheme);
        // A brief dip makes the palette swap read as a deliberate transition.
        FadeIn(Dashboard, 0.94, 120);
        if (!await RememberPreferencesAsync()) ShowStatus("Theme changed", "The theme could not be saved for future sessions.", true);
    }

    private async void OnChooseBat(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        var picker = new OpenFileDialog { Title = "Connect the HWID BAT scanner", Filter = "HWID batch scanner (*.bat)|*.bat", CheckFileExists = true };
        if (picker.ShowDialog(this) != true) return;
        ConnectEngine(picker.FileName);
        if (_engine != null)
        {
            if (!await RememberPreferencesAsync()) ShowStatus("BAT connected", "The connection works for this session. Its path could not be saved.", true);
            await RefreshSnapshotsAsync();
        }
    }
    private async void OnNavigate(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string page }) return;
        Navigate(page);
        if (page == "Snapshots") await RefreshSnapshotsAsync();
    }
    private void Navigate(string page)
    {
        if (!_initialized) return;
        var pages = new Dictionary<string, FrameworkElement> { ["Overview"] = OverviewPage, ["Identifiers"] = IdentifiersPage, ["Hardware"] = HardwarePage, ["Review"] = ReviewPage, ["Snapshots"] = SnapshotsPage, ["Compare"] = ComparePage };
        if (!pages.ContainsKey(page)) page = "Overview";
        var changed = _page != page;
        foreach (var pair in pages)
        {
            ResetPageMotion(pair.Value);
            pair.Value.Visibility = pair.Key == page ? Visibility.Visible : Visibility.Collapsed;
        }
        foreach (var button in new[] { OverviewNav, IdentifiersNav, HardwareNav, ReviewNav, SnapshotsNav, CompareNav })
        {
            var active = (string)button.Tag == page;
            if (active)
            {
                button.SetResourceReference(BackgroundProperty, "NavActiveBrush");
                button.SetResourceReference(BorderBrushProperty, "AccentBrush");
                button.BorderThickness = new Thickness(3, 0, 0, 0);
            }
            else
            {
                button.Background = Brushes.Transparent;
                button.BorderThickness = new Thickness(0);
            }
            button.SetResourceReference(ForegroundProperty, active ? "AccentBrush" : "MutedBrush");
            System.Windows.Automation.AutomationProperties.SetItemStatus(button, active ? "Current page" : "");
        }
        _page = page;
        (PageTitle.Text, PageSubtitle.Text) = page switch
        {
            "Identifiers" => ("ID numbers & serials", "Exact values, with missing and default fields clearly labeled."),
            "Hardware" => ("Hardware inventory", "Browse every captured section, device and reported field."),
            "Review" => ("Warnings & review", "Understand read failures, missing identifiers and conflicting observations."),
            "Snapshots" => ("Saved snapshots", "Find earlier captures and compare them with your current scan."),
            "Compare" => ("Compare IDs", "See the previous value, current value and exact difference."),
            _ => ("Overview", "A clear view of the identifiers Windows reports.")
        };
        if (changed && UiMotion.GetEnabled(this) && !_closing)
        {
            // Fade plus a short upward slide so switching tabs reads as motion.
            var element = pages[page];
            var slide = element.RenderTransform as TranslateTransform ?? new TranslateTransform();
            element.RenderTransform = slide;
            slide.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(6, 0, TimeSpan.FromMilliseconds(140))
            {
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
                FillBehavior = FillBehavior.Stop
            });
            FadeIn(element, 0.88, 140, () => ResetPageMotion(element));
        }
    }
    private void StopFade(FrameworkElement element)
    {
        element.ApplyAnimationClock(OpacityProperty, null);
        element.Opacity = 1;
        _fadeClocks.Remove(element);
    }

    private void ResetPageMotion(FrameworkElement element)
    {
        StopFade(element);
        if (element.RenderTransform is TranslateTransform slide)
        {
            slide.BeginAnimation(TranslateTransform.YProperty, null);
            slide.Y = 0;
        }
    }

    private void FadeIn(FrameworkElement element, double from, int milliseconds, Action? completed = null)
    {
        StopFade(element);
        if (!UiMotion.GetEnabled(this) || _closing || !element.IsVisible) { completed?.Invoke(); return; }
        var clock = new DoubleAnimation(from, 1, TimeSpan.FromMilliseconds(milliseconds)) { FillBehavior = FillBehavior.Stop }.CreateClock();
        _fadeClocks[element] = clock;
        clock.Completed += (_, _) =>
        {
            if (!_fadeClocks.TryGetValue(element, out var active) || !ReferenceEquals(active, clock)) return;
            StopFade(element);
            completed?.Invoke();
        };
        element.ApplyAnimationClock(OpacityProperty, clock, HandoffBehavior.SnapshotAndReplace);
    }

    protected override void OnPropertyChanged(DependencyPropertyChangedEventArgs e)
    {
        base.OnPropertyChanged(e);
        if (!_initialized || e.Property != UiMotion.EnabledProperty || UiMotion.GetEnabled(this)) return;
        foreach (var element in _fadeClocks.Keys.ToArray()) StopFade(element);
        foreach (var page in PageHost.Children.OfType<FrameworkElement>()) ResetPageMotion(page);
        FinishWindowFade();
    }

    private void BeginWindowFade(Action completed)
    {
        _closeCompletion = completed;
        IsEnabled = false;
        foreach (var element in _fadeClocks.Keys.ToArray()) StopFade(element);
        if (!UiMotion.GetEnabled(this) || Opacity <= 0) { FinishWindowFade(); return; }
        var fade = new DoubleAnimation(Opacity, 0, TimeSpan.FromMilliseconds(120));
        fade.Completed += (_, _) => FinishWindowFade();
        BeginAnimation(OpacityProperty, fade, HandoffBehavior.SnapshotAndReplace);
    }

    private void FinishWindowFade()
    {
        if (_closeCompletion == null || _closeCompletionQueued) return;
        _closeCompletionQueued = true;
        BeginAnimation(OpacityProperty, null);
        Dispatcher.BeginInvoke(new Action(() =>
        {
            var completed = _closeCompletion;
            _closeCompletion = null;
            _closeCompletionQueued = false;
            completed?.Invoke();
        }));
    }
    private Task FocusSearch()
    {
        TextBox? target = _page switch
        {
            "Identifiers" => IdSearch,
            "Review" => ReviewSearch,
            "Hardware" => HardwareSearch,
            _ => null
        };
        if (target == null) { ShowStatus("Search", "This page has no search box. Search is available on IDs, Review and Hardware."); }
        else { target.Focus(); target.SelectAll(); }
        return Task.CompletedTask;
    }

    private void ShowStatus(string title, string detail, bool warning = false)
    {
        if (_closing) return;
        StatusTitle.Text = title;
        SetSummary(StatusDetail, detail);
        StatusTitle.SetResourceReference(TextBlock.ForegroundProperty, warning ? "WarningBrush" : "AccentBrush");
    }
    private static void SetSummary(TextBlock label, string text, string? fullText = null)
    {
        label.Text = text.ReplaceLineEndings(" ");
        label.ToolTip = fullText ?? text;
    }
    private void ShowError(string title, Exception ex) => ShowStatus(title, ex.Message.Length > 1800 ? ex.Message[..1800] : ex.Message, true);
    private void SetBusy(bool busy, string operation = "")
    {
        if (busy) _operationFinished = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        _busy = busy; _operation = operation;
        var scanning = busy && operation == "Scan";
        MetricsGrid.Visibility = scanning ? Visibility.Collapsed : Visibility.Visible;
        OverviewComputerCard.Visibility = scanning ? Visibility.Collapsed : Visibility.Visible;
        CancelButton.Visibility = busy && operation == "Scan" ? Visibility.Visible : Visibility.Collapsed;
        CancelButton.IsEnabled = true;
        UpdateButtons();
        if (!busy) _operationFinished?.TrySetResult(true);
    }
    private void UpdateButtons()
    {
        if (!_initialized) return;
        ScanButton.IsEnabled = !_busy && _engine != null;
        ConnectButton.IsEnabled = !_busy;
        RestartButton.IsEnabled = !_busy;
        SaveButton.IsEnabled = !_busy && _snapshot != null && _engine != null;
        ExportButton.IsEnabled = !_busy && _snapshot != null;
        CompareFilesButton.IsEnabled = !_busy && _engine != null;
        CompareCurrentButton.IsEnabled = !_busy && _snapshot != null && _engine != null;
        CompareExportButton.IsEnabled = !_busy && _lastComparisonRows != null;
        CompareSelectedButton.IsEnabled = !_busy && _snapshot != null && SnapshotsGrid.SelectedItem is SnapshotEntry;
        SnapshotFolderSettingsButton.IsEnabled = !_busy && (!IsVerification || VerificationSharedSettingsPath != null);
        UpdatesButton.IsEnabled = !IsVerification;
        UpdateEmptyStates();
        CommandManager.InvalidateRequerySuggested();
    }
    private void UpdateEmptyStates()
    {
        if (!_initialized) return;
        var scanning = _busy && _operation == "Scan";
        var reviewHasRows = ReviewGrid.Items.Count > 0;
        ReviewGrid.Visibility = reviewHasRows ? Visibility.Visible : Visibility.Collapsed;
        ReviewEmptyState.Visibility = reviewHasRows ? Visibility.Collapsed : Visibility.Visible;
        ReviewDetail.Visibility = reviewHasRows ? Visibility.Visible : Visibility.Collapsed;
        ReviewDetailRow.MinHeight = reviewHasRows ? 66 : 0;
        ReviewDetailRow.Height = new GridLength(reviewHasRows ? 0.52 : 0, GridUnitType.Star);
        var findings = _snapshot?.Findings.Count ?? 0;
        ReviewResultsText.Text = _snapshot == null ? scanning ? "Scanning…" : "No scan yet" :
            (findings == 0 ? "No review items" : $"{ReviewGrid.Items.Count} of {findings} shown") + (scanning ? " · last scan" : "");
        if (!reviewHasRows)
        {
            if (_snapshot != null && findings > 0)
            {
                ReviewEmptyTitle.Text = "No findings match this search";
                ReviewEmptyText.Text = "Clear the search to show all review items, or try another word.";
                ReviewEmptyAction.Content = "Clear search";
                ReviewEmptyAction.Tag = "ClearReview";
            }
            else if (scanning)
            {
                ReviewEmptyTitle.Text = _snapshot == null ? "Scan in progress" : "The last scan reported no review items";
                ReviewEmptyText.Text = _snapshot == null ? "Review items will appear when this scan finishes." :
                    "A new scan is running. This page will update after it finishes.";
                ReviewEmptyAction.Content = "View scan progress";
                ReviewEmptyAction.Tag = "Overview";
            }
            else if (_snapshot == null)
            {
                ReviewEmptyTitle.Text = "Start a scan to review this PC";
                ReviewEmptyText.Text = _engine == null ? "Connect hwid.bat, then scan to see warnings and sections Windows could not read." :
                    "Warnings, missing identifiers and unread sections will be explained here.";
                ReviewEmptyAction.Content = _engine == null ? "Connect BAT…" : "Scan this PC";
                ReviewEmptyAction.Tag = _engine == null ? "Connect" : "Scan";
            }
            else
            {
                ReviewEmptyTitle.Text = "No review items reported";
                ReviewEmptyText.Text = "Open Hardware to inspect the captured values and each section's read status.";
                ReviewEmptyAction.Content = "Browse hardware";
                ReviewEmptyAction.Tag = "Hardware";
            }
            ReviewEmptyAction.IsEnabled = !_busy || (string?)ReviewEmptyAction.Tag is "Overview" or "ClearReview" or "Hardware";
        }

        var hasChanges = CompareGrid.Items.Count > 0;
        var comparing = _busy && _operation == "Compare";
        var hasComparison = _lastComparisonRows != null;
        CompareGrid.Visibility = hasChanges ? Visibility.Visible : Visibility.Collapsed;
        CompareEmptyState.Visibility = hasChanges ? Visibility.Collapsed : Visibility.Visible;
        CompareDetailPanel.Visibility = hasComparison || hasChanges ? Visibility.Visible : Visibility.Collapsed;
        CompareSkippedText.Visibility = hasChanges ? Visibility.Visible : Visibility.Collapsed;
        CompareDetailRow.MinHeight = hasComparison || hasChanges ? Dashboard.ActualHeight < 600 ? 66 : 76 : 0;
        CompareDetailRow.Height = new GridLength(hasComparison || hasChanges ? 0.5 : 0, GridUnitType.Star);
        if (comparing)
            CompareSummaryText.Text = hasComparison ? "Comparing… previous results remain below." : "Comparing the selected captures…";
        else if (scanning && hasComparison)
            CompareSummaryText.Text = "Previous comparison · a new scan is running";
        else if (hasComparison)
            CompareSummaryText.Text = hasChanges ? _lastComparisonSummary : "Comparison finished";
        else
            CompareSummaryText.Text = "Choose a current scan or two saved captures.";
        CompareEmptyAction.Visibility = comparing || hasComparison ? Visibility.Collapsed : Visibility.Visible;
        CompareEmptyAction.IsEnabled = !_busy;
        if (comparing)
        {
            CompareEmptyTitle.Text = "Comparing snapshots";
            CompareEmptyText.Text = "Reading the selected captures and matching the identifier fields supported by the scanner.";
        }
        else if (!hasComparison && scanning)
        {
            CompareEmptyTitle.Text = "Your current scan is still running";
            CompareEmptyText.Text = "When it finishes, choose an older JSON capture to compare with this PC, or choose two saved files.";
            CompareEmptyAction.Content = "View scan progress";
            CompareEmptyAction.Tag = "Overview";
            CompareEmptyAction.IsEnabled = true;
        }
        else if (!hasComparison)
        {
            CompareEmptyTitle.Text = "Choose what to compare";
            CompareEmptyText.Text = _snapshot == null ? "Start a scan and compare it with an older JSON capture, or use Two saved files to compare captures already on disk." :
                "Use Current scan to select an older JSON capture, or use Two saved files to compare captures already on disk.";
            CompareEmptyAction.Content = _engine == null ? "Connect BAT…" : _snapshot == null ? "Scan this PC" : "Compare with current scan…";
            CompareEmptyAction.Tag = _engine == null ? "Connect" : _snapshot == null ? "Scan" : "CompareCurrent";
        }
        else
        {
            CompareEmptyTitle.Text = _comparisonSameFile ? "The same file was selected twice" :
                !_comparisonHasFields ? "No identifier fields could be compared" : "No changes in the fields compared";
            CompareEmptyText.Text = _comparisonSameFile ? "Both sides use the same JSON file path. Choose different saved captures to compare two scans." :
                !_comparisonHasFields ? "One or both captures lack usable values for comparison. Read the notes below." :
                _comparisonHasGaps ? "No differences were reported. Some information was skipped; read the notes below." :
                "The compared identifier values match. You can export this result or choose another comparison above.";
            CompareEmptyAction.Content = "Choose another comparison…";
            CompareEmptyAction.Tag = _snapshot == null ? "CompareFiles" : "CompareCurrent";
        }
    }

    private async void OnEmptyStateAction(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string action }) return;
        switch (action)
        {
            case "ClearReview": ReviewSearch.Clear(); break;
            case "Scan": await RunScanAsync(); break;
            case "Connect": OnChooseBat(sender, e); break;
            case "CompareCurrent": OnChooseComparison(sender, e); break;
            case "CompareFiles": OnChooseTwoFileComparison(sender, e); break;
            default: Navigate(action); break;
        }
    }
    private async void OnScan(object sender, RoutedEventArgs e) => await RunScanAsync();
    private async Task<bool> RunScanAsync()
    {
        if (_busy || _engine == null) return false;
        var generation = ++_scanGeneration;
        var completedScan = false;
        Navigate("Overview"); SetBusy(true, "Scan");
        _operationCancellation = new CancellationTokenSource();
        _scanClock.Restart();
        _scanCompletedStages = 0;
        _scanTotalStages = ScanSectionNames.Length;
        ScanRows.Clear();
        foreach (var section in ScanSectionNames) ScanRows.Add(new(section, "WAITING", "—", "Waiting for this section.", ""));
        ScanProgress.Value = 0;
        SnapshotContextText.Text = _snapshot == null ? "Preparing the first snapshot" :
            "Last completed snapshot · " + _snapshot.Info.Text("Computer") + " · " + J.Date(_snapshot.Info.Text("Generated"));
        ShowStatus("Scanning this PC", _snapshot == null ? "Reading hardware information from Windows. You can cancel and try again." : "Reading a new capture. Your last completed scan remains available until this one finishes.");
        try
        {
            var progress = new Progress<BridgeProgress>(value => ApplyScanProgress(value, generation));
            var result = await _engine.ScanAsync(progress, _operationCancellation.Token);
            var candidate = new DesktopSnapshot(result);
            ApplySnapshot(candidate);
            completedScan = true;
            ScanProgress.Value = 100;
            var complete = candidate.SectionsRead == 18 && candidate.Info.Text("ExtendedStatus") == "Refreshed";
            ShowStatus(complete ? "Scan complete" : "Scan complete with unread sections",
                $"{candidate.SectionsRead} of 18 sections read · {candidate.ReportedIds} identifier fields supplied · " +
                (candidate.Findings.Count == 0 ? "No review items reported. " : $"{candidate.Findings.Count} items explained in Review. ") +
                (candidate.Info.Text("ExtendedStatus") == "Refreshed" ? "Device list refreshed." : "The device list could not be refreshed. Open Review or Hardware for details."), !complete);
            return true;
        }
        catch (OperationCanceledException) { RestoreScanActivity(); ShowStatus("Scan cancelled", _snapshot == null ? "Start a new scan when you are ready." : "Your last completed snapshot is still active.", true); return false; }
        catch (Exception ex) { RestoreScanActivity(); ShowError("Scan could not finish", ex); return false; }
        finally
        {
            ++_scanGeneration;
            _scanClock.Stop();
            Title = "HWID Checker — Desktop";
            ScanElapsedText.Text = (completedScan ? "Scan time · " : "Last attempt · ") + _scanClock.Elapsed.ToString(@"mm\:ss");
            SnapshotContextText.Text = _snapshot == null ? "No completed snapshot" : "Current completed snapshot";
            SetBusy(false);
            _operationCancellation?.Dispose();
            _operationCancellation = null;
        }
    }
    private void ApplyScanProgress(BridgeProgress value, int? generation = null)
    {
        if (!_busy || _operation != "Scan" || _closing || _closeRequested ||
            _operationCancellation?.IsCancellationRequested == true || generation.HasValue && generation != _scanGeneration) return;
        _scanTotalStages = Math.Max(1, value.Total);
        _scanCompletedStages = Math.Clamp(value.Completed, 0, _scanTotalStages);
        ScanProgress.Value = value.Total > 0 ? Math.Clamp(100d * value.Completed / value.Total, 0, 100) : 0;
        Title = "HWID Checker — Desktop · scanning " + Math.Round(ScanProgress.Value) + "%";
        var name = string.IsNullOrWhiteSpace(value.Name) ? value.Section : value.Name;
        if (string.IsNullOrWhiteSpace(name)) return;
        if (name == "Preparing") { ShowStatus("Preparing scanner", value.Message); return; }
        if (name == "Extended device inventory") name = "All-known device catalog";
        var finished = value.Status is not ("READING" or "WAITING" or "");
        var detail = value.Message;
        if (!string.IsNullOrWhiteSpace(value.FailureCode) && !detail.Contains(value.FailureCode, StringComparison.OrdinalIgnoreCase))
            detail += " · " + value.FailureCode;
        if (!string.IsNullOrWhiteSpace(value.NextStep) && !detail.Contains(value.NextStep, StringComparison.OrdinalIgnoreCase))
            detail += " · Next step · " + value.NextStep;
        var row = new ScanRow(name, value.Status == "UNAVAILABLE" ? "NOT READ" : value.Status,
            finished ? value.Records.ToString() : "—", detail,
            value.Seconds is { } seconds ? seconds.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture) + " s" : "");
        var existing = ScanRows.Select((item, index) => (item, index)).FirstOrDefault(entry => entry.item.Name == name);
        if (existing.item != null) ScanRows[existing.index] = row;
        else ScanRows.Add(row);
        StatusTitle.Text = "Scanning this PC";
        SetSummary(StatusDetail, name + " · " + value.Message);
    }
    private void ApplySnapshot(DesktopSnapshot snapshot)
    {
        var previousSection = (HardwareSections.SelectedItem as HardwareSection)?.Name;
        _snapshot = snapshot;
        IdsCount.Text = snapshot.ReportedIds.ToString("N0"); SectionsCount.Text = snapshot.SectionsRead + " / 18";
        ReviewCount.Text = snapshot.Findings.Count.ToString("N0"); DevicesCount.Text = snapshot.DeviceCount.ToString("N0");
        SetSummary(ComputerText, string.IsNullOrWhiteSpace(snapshot.Info.Text("Computer")) ? "Not supplied" : snapshot.Info.Text("Computer"));
        SetSummary(CapturedText, "Captured · " + J.Date(snapshot.Info.Text("Generated")));
        var model = string.Join(" · ", new[] { snapshot.First("System hardware", "Manufacturer"), snapshot.First("System hardware", "Model") }
            .Where(value => !string.IsNullOrWhiteSpace(value)));
        SetSummary(PcModelText, model.Length == 0 ? "Model · not supplied" : model);
        SetSummary(CpuText, snapshot.First("CPU", "Name"));
        SnapshotContextText.Text = "Current completed snapshot";
        var ram = snapshot.First("System hardware", "TotalRAM_GiB"); MemoryText.Text = ram.Length > 0 ? "Memory · " + ram + " GiB" : "Memory · not supplied";
        WindowsText.Text = snapshot.First("Windows", "Caption"); CatalogText.Text = "Catalog · " + snapshot.Info.Text("ExtendedStatus");
        EngineVersionText.Text = "Scanner v" + snapshot.Version;
        PopulateScanRows(snapshot);
        IdentifiersGrid.SelectedIndex = -1;
        ReviewGrid.SelectedIndex = -1;
        FilterIds();
        ReviewGrid.ItemsSource = _snapshot == null ? null : _snapshot.Findings;
        FilterReview();
        IdDetail.Clear(); ReviewDetail.Clear(); HardwareDetail.Clear();
        CompareGrid.ItemsSource = Array.Empty<ChangeRow>();
        CompareSummaryText.Text = "Choose a saved JSON to compare with this scan.";
        SetSummary(CompareBaselineText, "Baseline not selected");
        SetSummary(CompareSkippedText, "");
        _lastComparisonRows = null;
        _comparisonHasFields = _comparisonHasGaps = _comparisonSameFile = false;
        CompareExportButton.IsEnabled = false;
        CompareDetail.Clear();
        HardwareSections.SelectedIndex = -1;
        var sections = snapshot.Sections.OrderBy(section => section.Name == "System hardware" ? 0 :
            section.Name is "Report info" or "Compatibility" or "Scan timing" or "Warnings" or "Extended scan info" ? 2 : 1).ToArray();
        HardwareSections.ItemsSource = sections;
        HardwareSections.SelectedItem = sections.FirstOrDefault(section => section.Name == previousSection) ??
            sections.FirstOrDefault(section => section.Name == "System hardware" && section.Count > 0) ??
            sections.FirstOrDefault(section => section.Name == "CPU" && section.Count > 0) ??
            sections.FirstOrDefault(section => section.Count > 0 && ScanSectionNames.Contains(section.Name)) ??
            sections.FirstOrDefault(section => section.Name == "Extended device inventory" && section.Count > 0) ??
            sections.FirstOrDefault();
        UpdateButtons();
    }
    private void PopulateScanRows(DesktopSnapshot snapshot)
    {
        ScanElapsedText.Text = $"{snapshot.Timing.Count} sections + device catalog";
        ScanRows.Clear(); foreach (var row in snapshot.Timing) ScanRows.Add(row);
        var catalog = snapshot.Inventory.Get("Extended scan info");
        ScanRows.Add(new("All-known device catalog", snapshot.Info.Text("ExtendedStatus") == "Refreshed" ? "READ" : "NOT READ", snapshot.DeviceCount.ToString(),
            catalog.Number("ParentLinkConflicts") > 0 ? catalog.Number("ParentLinkConflicts") + " unresolved parent links" : "Present, hidden and remembered Windows records", ""));
    }
    private void RestoreScanActivity()
    {
        if (_snapshot != null)
        {
            PopulateScanRows(_snapshot);
            ScanProgress.Value = 100;
        }
        else
        {
            for (var i = 0; i < ScanRows.Count; i++)
                if (ScanRows[i].Status is "READING" or "WAITING" or "") ScanRows[i] = ScanRows[i] with { Status = "Stopped", Detail = "This attempt did not produce a completed snapshot." };
            ScanProgress.Value = 0;
        }
    }
    private void OnCancel(object sender, RoutedEventArgs e)
    {
        CancelButton.IsEnabled = false;
        _operationCancellation?.Cancel();
        ShowStatus("Cancelling scan…", "Waiting for the scanner process to stop.");
    }
    private void OnIdFilterChanged(object sender, RoutedEventArgs e) { if (_initialized) FilterIds(); }
    private void OnReviewFilterChanged(object sender, RoutedEventArgs e) { if (_initialized) FilterReview(); }
    private void FilterReview()
    {
        if (!_initialized) return;
        var needle = ReviewSearch.Text.Trim();
        ReviewGrid.ItemsSource = _snapshot == null ? null : _snapshot.Findings.Where(x =>
            needle.Length == 0 || string.Join(" ", x.Kind, x.Section, x.Message, x.Detail).Contains(needle, StringComparison.OrdinalIgnoreCase)).ToArray();
        UpdateEmptyStates();
    }
    private void FilterIds()
    {
        if (!_initialized) return;
        var needle = IdSearch.Text.Trim(); var filter = IdFilter.SelectedIndex;
        IdentifiersGrid.ItemsSource = (_snapshot?.Identifiers ?? []).Where(x =>
            (filter != 1 || x.Status == "Reported") && (filter != 2 || x.Status is "Missing" or "Default") &&
            (needle.Length == 0 || string.Join(" ", x.Section, x.Field, x.Value, x.Device).Contains(needle, StringComparison.OrdinalIgnoreCase))).ToArray();
    }
    private void OnIdSelected(object sender, SelectionChangedEventArgs e) { IdDetail.Text = IdentifiersGrid.SelectedItem is IdentifierRow row ? row.Device + "\n" + row.Field + ": " + (row.Value.Length > 0 ? row.Value : "(not supplied)") : ""; }
    private void OnIdDoubleClicked(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is DependencyObject source &&
            ItemsControl.ContainerFromElement(IdentifiersGrid, source) is DataGridRow { Item: IdentifierRow row } && row.Value.Length > 0)
            Copy(row.Value);
    }
    private void OnCopyAllIds(object sender, RoutedEventArgs e)
    {
        var lines = (IdentifiersGrid.ItemsSource as IEnumerable<IdentifierRow>)?
            .Select(row => row.Section + " · " + row.Field + " · " + (row.Value.Length > 0 ? row.Value : "(not supplied)")).ToArray();
        if (lines == null || lines.Length == 0) { ShowStatus("Nothing to copy", "Run a scan first, then copy the identifier list."); return; }
        Copy(string.Join(Environment.NewLine, lines));
    }
    private void OnCopyId(object sender, RoutedEventArgs e) { if (IdentifiersGrid.SelectedItem is IdentifierRow row) Copy(row.Value); }
    private void Copy(string text)
    {
        if (text.Length == 0) { ShowStatus("No value to copy", "Windows did not supply this identifier.", true); return; }
        try
        {
            Clipboard.SetText(text);
            ShowStatus("Copied to clipboard", text.Length > 90 ? text[..90] + "\u2026" : text);
        }
        catch (Exception ex) { ShowError("Could not copy this value", ex); }
    }
    private void OnHardwareSectionSelected(object sender, SelectionChangedEventArgs e)
    {
        if (_snapshot == null || HardwareSections.SelectedItem is not HardwareSection section)
        {
            HardwareSectionTitle.Text = "Hardware fields";
            SetSummary(HardwareCountText, "No records");
            HardwareSectionPicker.ToolTip = null;
            HardwareRecord.ItemsSource = null;
            HardwareFields.ItemsSource = null;
            HardwareDetail.Clear();
            return;
        }
        SetSummary(HardwareSectionTitle, section.FriendlyName, section.Display);
        SetSummary(HardwareCountText, section.CountText, section.Display);
        HardwareSectionPicker.ToolTip = section.Display;
        HardwareSearch.ToolTip = "Search records in this section. " + DesktopSnapshot.SectionDescription(section.Name);
        PopulateHardwareRecords(section);
    }
    private void PopulateHardwareRecords(HardwareSection section)
    {
        if (_snapshot == null) return;
        var needle = HardwareSearch.Text.Trim();
        HardwareRecord.ItemsSource = _snapshot.Inventory.Get(section.Name).Rows()
            .Select((value, index) => (value, index, title: new[] { "FriendlyName", "Name", "Model", "DeviceLocator", "DeviceID", "Section" }.Select(name => value.Text(name)).FirstOrDefault(x => !string.IsNullOrWhiteSpace(x))))
            .Where(entry => needle.Length == 0 || entry.title?.Contains(needle, StringComparison.OrdinalIgnoreCase) == true ||
                HardwareValueMatches(entry.value, needle))
            .Select(entry => new HardwareRecord(_snapshot.RecordTitle(section.Name, entry.value, entry.index), entry.value, entry.index))
            .ToArray();
        HardwareRecord.SelectedIndex = HardwareRecord.Items.Count > 0 ? 0 : -1;
        if (HardwareRecord.Items.Count == 0) { HardwareFields.ItemsSource = Array.Empty<FieldRow>(); HardwareDetail.Text = needle.Length == 0 ? "No records captured for this section." : "No records in this section match the search."; }
    }
    private static bool HardwareValueMatches(JsonElement value, string needle) => value.ValueKind switch
    {
        JsonValueKind.Object => value.EnumerateObject().Any(field => HardwareValueMatches(field.Value, needle)),
        JsonValueKind.Array => value.EnumerateArray().Any(item => HardwareValueMatches(item, needle)),
        _ => value.Text().Contains(needle, StringComparison.OrdinalIgnoreCase)
    };
    private void OnHardwareFilterChanged(object sender, RoutedEventArgs e)
    {
        if (_initialized && _snapshot != null && HardwareSections.SelectedItem is HardwareSection section) PopulateHardwareRecords(section);
    }
    private void OnHardwareRecordSelected(object sender, SelectionChangedEventArgs e)
    {
        if (_snapshot == null || HardwareSections.SelectedItem is not HardwareSection section || HardwareRecord.SelectedItem is not HardwareRecord record)
        {
            HardwareFields.ItemsSource = null;
            HardwareDetail.Clear();
            return;
        }
        HardwareFields.ItemsSource = record.Data.ValueKind == JsonValueKind.Object ? record.Data.EnumerateObject().Select(field =>
            new FieldRow(_snapshot.Label(section.Name, field.Name), _snapshot.FieldValue(section.Name, record.Index, field.Name, field.Value),
                field.Value.ValueKind is JsonValueKind.Array or JsonValueKind.Object ? field.Value.GetRawText() : field.Value.Text())).ToArray() :
            [new FieldRow("Value", record.Data.Display(), record.Data.ValueKind is JsonValueKind.Array or JsonValueKind.Object ? record.Data.GetRawText() : record.Data.Text())];
        HardwareDetail.Text = "Select a field for the full value.";
    }
    private void OnHardwareFieldSelected(object sender, SelectionChangedEventArgs e)
    {
        HardwareDetail.Text = HardwareFields.SelectedItem is FieldRow field
            ? field.Field + "\n" + field.Value + (field.RawValue != null && field.RawValue != field.Value ? "\n\nOriginal value\n" + field.RawValue : "")
            : "Select a field for the full value.";
    }
    private void OnCopyField(object sender, RoutedEventArgs e) { if (HardwareFields.SelectedItem is FieldRow field) Copy(field.RawValue ?? field.Value); }
    private void OnReviewSelected(object sender, SelectionChangedEventArgs e) { ReviewDetail.Text = ReviewGrid.SelectedItem is ReviewRow row ? row.Message + "\n\n" + row.Detail : ""; }

    private SnapshotLibrarySettings ReadSharedLibrary() =>
        IsVerification && VerificationSharedSettingsPath == null
            ? new SnapshotLibrarySettings(null, [])
            : SharedSnapshotLibrary.Read(VerificationSharedSettingsPath);

    private IEnumerable<string> SaveFolderCandidates(SnapshotLibrarySettings settings)
    {
        if (settings.Primary is { } primary) yield return primary;
        yield return DefaultReportsFolder;
        if (!IsVerification) yield return LocalReportsFolder;
    }

    private static bool SameFolder(string left, string right) =>
        Path.TrimEndingDirectorySeparator(left).Equals(Path.TrimEndingDirectorySeparator(right), StringComparison.OrdinalIgnoreCase);

    private string EnsureSaveFolder(SnapshotLibrarySettings settings)
    {
        Exception? failure = null;
        foreach (var folder in SaveFolderCandidates(settings).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            try { return Directory.CreateDirectory(folder).FullName; }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException) { failure = ex; }
        }
        throw new IOException("Could not prepare a report folder. " + failure?.Message, failure);
    }

    private IEnumerable<string> BuiltInReportFolders()
    {
        yield return DefaultReportsFolder;
        if (!IsVerification) yield return LocalReportsFolder;
        if (_engine != null)
        {
            var directory = Path.GetDirectoryName(_engine.BatPath)!; var parent = Directory.GetParent(directory)?.FullName;
            if (parent != null && File.Exists(Path.Combine(parent, "hwid.bat"))) yield return Path.Combine(parent, "HWID-Reports");
            string[] children;
            try { children = Directory.GetDirectories(directory); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { children = []; }
            foreach (var child in children.Where(x => File.Exists(Path.Combine(x, "hwid.bat")))) yield return Path.Combine(child, "HWID-Reports");
        }
    }

    private IEnumerable<string> ReportFolders(SnapshotLibrarySettings? settings = null)
    {
        settings ??= ReadSharedLibrary();
        if (settings.Primary is { } primary) yield return primary;
        foreach (var folder in settings.Folders) yield return folder;
        foreach (var folder in BuiltInReportFolders()) yield return folder;
        if (!settings.IsConfigured)
        {
            if (_lastSaveFolder.Length > 0) yield return _lastSaveFolder;
            foreach (var folder in _additionalFolders) yield return folder;
        }
    }

    private void ShowSnapshotFolders(SnapshotLibrarySettings settings, IReadOnlyList<string>? searchedFolders = null)
    {
        var folder = settings.Primary ?? DefaultReportsFolder;
        var label = (settings.Primary == null ? "Default save folder: " : "Shared save folder: ") + folder;
        var text = settings.Error == null ? label : "Shared settings unavailable · " + label;
        var details = settings.Error == null ? label : label + Environment.NewLine + settings.Error;
        if (searchedFolders is { Count: > 0 })
            details += Environment.NewLine + Environment.NewLine + "Searched locations:" + Environment.NewLine + string.Join(Environment.NewLine, searchedFolders);
        SnapshotFoldersText.SetResourceReference(TextBlock.ForegroundProperty, settings.Error == null ? "MutedBrush" : "WarningBrush");
        SetSummary(SnapshotFoldersText, text, details);
    }
    private Task RefreshSnapshotsAsync()
    {
        if (_closing) return Task.CompletedTask;
        _refreshAgain = true;
        if (_snapshotRefreshTask is { IsCompleted: false }) return _snapshotRefreshTask;
        return _snapshotRefreshTask = RefreshSnapshotLoopAsync();
    }
    private async Task RefreshSnapshotLoopAsync()
    {
        try
        {
          do
          {
            _refreshAgain = false;
            var settings = ReadSharedLibrary();
            ShowSnapshotFolders(settings);
            var catalog = await SnapshotStore.ReadAsync(ReportFolders(settings).ToArray());
            if (_closing || _closeRequested) return;
            if (SnapshotsGrid.ItemsSource is not IEnumerable<SnapshotEntry> displayed || !displayed.SequenceEqual(catalog.Entries))
            {
                var selectedPath = (SnapshotsGrid.SelectedItem as SnapshotEntry)?.Path;
                SnapshotsGrid.ItemsSource = catalog.Entries;
                SnapshotsGrid.SelectedItem = catalog.Entries.FirstOrDefault(x => x.Path.Equals(selectedPath, StringComparison.OrdinalIgnoreCase));
                // Brief fade so a refreshed list reads as refreshed, not shuffled.
                if (_page == "Snapshots" && !_busy) FadeIn(SnapshotsGrid, 0.9, 120);
            }
            SetSummary(SnapshotCountText, $"{catalog.Entries.Count} saved captures found" +
                (catalog.Skipped > 0 ? $" · {catalog.Skipped} unreadable or unrecognized files/folders skipped" : " · JSON is validated again before comparison"));
            ShowSnapshotFolders(settings, catalog.Folders);
            UpdateButtons();
          } while (_refreshAgain && !_closing);
        }
        catch (Exception ex) { SetSummary(SnapshotCountText, "Could not refresh snapshots: " + ex.Message); }
    }
    private async void OnRefreshSnapshots(object sender, RoutedEventArgs e) => await RefreshSnapshotsAsync();
    private async void OnSnapshotFolderSettings(object sender, RoutedEventArgs e)
    {
        if (_busy || (IsVerification && VerificationSharedSettingsPath == null)) return;
        var dialog = new SnapshotFolderDialog(ReadSharedLibrary(), DefaultReportsFolder, VerificationSharedSettingsPath) { Owner = this };
        dialog.ShowDialog();
        await RefreshSnapshotsAsync();
    }
    private void OnSnapshotSelected(object sender, SelectionChangedEventArgs e)
    {
        var row = SnapshotsGrid.SelectedItem as SnapshotEntry;
        SetSummary(SnapshotSelectedPath, row?.Name ?? "Select a snapshot to compare.", row?.Path);
        UpdateButtons();
    }
    private async void OnSnapshotDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (!_busy && _snapshot != null && e.OriginalSource is DependencyObject source &&
            ItemsControl.ContainerFromElement(SnapshotsGrid, source) is DataGridRow { Item: SnapshotEntry row })
        {
            await CompareAsync(row.Path);
        }
    }
    private async void OnCompareSelected(object sender, RoutedEventArgs e) { if (SnapshotsGrid.SelectedItem is SnapshotEntry row) await CompareAsync(row.Path); }
    private async void OnChooseComparison(object sender, RoutedEventArgs e)
    {
        if (_snapshot == null) { ShowStatus("Scan this PC first", "Comparison needs a completed current snapshot.", true); return; }
        if (_busy) return;
        var picker = new OpenFileDialog { Title = "Choose a previous HWID JSON snapshot", Filter = "JSON snapshot (*.json)|*.json", CheckFileExists = true };
        var starting = new[] { _lastSaveFolder }.Concat(SaveFolderCandidates(ReadSharedLibrary())).FirstOrDefault(Directory.Exists);
        if (starting != null) picker.InitialDirectory = starting;
        if (picker.ShowDialog(this) == true) await CompareAsync(picker.FileName);
    }
    private async Task CompareAsync(string previousPath)
    {
        if (_snapshot == null || _engine == null || _busy) return;
        SetBusy(true, "Compare"); _operationCancellation = new CancellationTokenSource();
        ShowStatus("Comparing snapshots", "Reading the saved capture and matching comparable identifier fields.");
        try
        {
            var result = await _engine.CompareAsync(previousPath, _snapshot.Inventory, _operationCancellation.Token);
            RenderComparison(result, previousPath, liveCurrent: true);
            Navigate("Compare"); ShowStatus("Comparison complete", _lastComparisonSummary + " Differences describe saved Windows records.",
                _lastComparisonRows!.Count > 0 || !_comparisonHasFields || _comparisonHasGaps || _comparisonSameFile);
        }
        catch (OperationCanceledException) { ShowStatus("Comparison cancelled", "The current scan remains available.", true); }
        catch (Exception ex) { ShowError("Could not compare this snapshot", ex); }
        finally { SetBusy(false); _operationCancellation?.Dispose(); _operationCancellation = null; }
    }

    private async void OnChooseTwoFileComparison(object sender, RoutedEventArgs e)
    {
        if (_engine == null) { ShowStatus("Connect the BAT first", "Comparisons run through the linked BAT engine.", true); return; }
        if (_busy) return;
        var candidates = SaveFolderCandidates(ReadSharedLibrary()).Where(Directory.Exists).ToList();
        if (_lastSaveFolder.Length > 0 && Directory.Exists(_lastSaveFolder)) candidates.Insert(0, _lastSaveFolder);
        var starting = candidates.FirstOrDefault();
        var previousPicker = new OpenFileDialog { Title = "Choose the OLDER saved snapshot (baseline)", Filter = "JSON snapshot (*.json)|*.json", CheckFileExists = true };
        if (starting != null) previousPicker.InitialDirectory = starting;
        if (previousPicker.ShowDialog(this) != true) return;
        var currentPicker = new OpenFileDialog { Title = "Choose the NEWER saved snapshot to compare against", Filter = "JSON snapshot (*.json)|*.json", CheckFileExists = true };
        var previousDirectory = Path.GetDirectoryName(previousPicker.FileName);
        if (previousDirectory != null && Directory.Exists(previousDirectory)) currentPicker.InitialDirectory = previousDirectory;
        if (currentPicker.ShowDialog(this) != true) return;
        await CompareFilesAsync(previousPicker.FileName, currentPicker.FileName);
    }

    private async Task CompareFilesAsync(string previousPath, string currentPath)
    {
        if (_engine == null || _busy) return;
        SetBusy(true, "Compare"); _operationCancellation = new CancellationTokenSource();
        ShowStatus("Comparing saved snapshots", "Reading both captures and matching comparable identifier fields.");
        try
        {
            var result = await _engine.CompareFilesAsync(previousPath, currentPath, _operationCancellation.Token);
            RenderComparison(result, previousPath, liveCurrent: false, savedCurrentPath: currentPath);
            Navigate("Compare"); ShowStatus("Comparison complete", _lastComparisonSummary + " Differences describe saved Windows records.",
                _lastComparisonRows!.Count > 0 || !_comparisonHasFields || _comparisonHasGaps || _comparisonSameFile);
        }
        catch (OperationCanceledException) { ShowStatus("Comparison cancelled", "Both saved snapshots remain available.", true); }
        catch (Exception ex) { ShowError("Could not compare these snapshots", ex); }
        finally { SetBusy(false); _operationCancellation?.Dispose(); _operationCancellation = null; }
    }

    private string CompareLabel(JsonElement result, string section, string field)
    {
        var label = result.Get("fieldLabels").Get(section).Text(field);
        if (label.Length > 0) return label;
        return _snapshot?.Label(section, field) ?? J.Humanize(field);
    }

    private void RenderComparison(JsonElement result, string previousPath, bool liveCurrent, string? savedCurrentPath = null)
    {
        var rows = result.Get("changes").Rows().Select(row => new ChangeRow(row.Text("kind"), row.Text("section") + " / " + CompareLabel(result, row.Text("section"), row.Text("field")),
            row.Get("previous").Display(), row.Get("current").Display(),
            "Device: " + row.Text("device") + "\nOLD: " + row.Get("previous").Display() + "\nNEW: " + row.Get("current").Display() + "\n\n" + row.Text("difference"))).ToArray();
        _lastComparisonRows = rows;
        _lastComparisonBaseline = "Previous: " + Path.GetFileName(previousPath) +
            (result.Text("previousComputer").Length > 0 ? " · " + result.Text("previousComputer") + " · " + J.Date(result.Text("previousCaptured")) : "");
        _lastComparisonCurrent = liveCurrent && _snapshot != null
            ? "Current: " + _snapshot.Info.Text("Computer") + " · " + J.Date(_snapshot.Info.Text("Generated"))
            : "Current: " + Path.GetFileName(savedCurrentPath ?? "") +
                (result.Text("currentComputer").Length > 0 ? " · " + result.Text("currentComputer") + " · " + J.Date(result.Text("currentCaptured")) : "");
        var changed = rows.Count(x => x.Kind == "Changed"); var added = rows.Count(x => x.Kind == "Current only"); var removed = rows.Count(x => x.Kind == "Previous only");
        _comparisonHasFields = result.Number("previousCount") > 0 && result.Number("currentCount") > 0;
        _comparisonHasGaps = result.Number("skippedFields") > 0 || result.Get("skippedSections").Rows().Length > 0 || result.Get("scopeWarnings").Rows().Length > 0;
        _comparisonSameFile = !liveCurrent && savedCurrentPath != null &&
            Path.GetFullPath(previousPath).Equals(Path.GetFullPath(savedCurrentPath), StringComparison.OrdinalIgnoreCase);
        _lastComparisonSummary = rows.Length > 0 ? $"{changed} changed · {added} only in newer capture · {removed} only in older capture" :
            !_comparisonHasFields ? "No identifier fields could be compared." : "No changes in the fields compared.";
        if (_comparisonSameFile) _lastComparisonSummary = "Same file selected twice · " + _lastComparisonSummary;
        CompareGrid.SelectedIndex = -1;
        CompareGrid.ItemsSource = rows;
        CompareSummaryText.Text = _lastComparisonSummary;
        SetSummary(CompareBaselineText, _lastComparisonBaseline + "   |   " + _lastComparisonCurrent, _lastComparisonBaseline + "\n" + previousPath + (liveCurrent ? "" : "\n" + savedCurrentPath) + "\n" + _lastComparisonCurrent);
        var notes = new List<string> { $"Identifier fields available for comparison · {result.Number("previousCount")} in the older capture, {result.Number("currentCount")} in the newer capture.", $"Not compared · {result.Number("skippedFields")} fields." };
        if (_comparisonSameFile) notes.Add("Both sides were read from the same JSON file path.");
        var skipped = result.Get("skippedSections").Rows().Select(x => x.Text()).ToArray();
        if (skipped.Length > 0) notes.Add("Unread sections: " + string.Join(", ", skipped) + ".");
        foreach (var scope in result.Get("scopeWarnings").Rows()) notes.Add("Reader coverage differs: " + scope.Text("PreviousReader") + " → " + scope.Text("CurrentReader") + "; " + scope.Number("SkippedDevices") + " unmatched device records not compared.");
        _lastComparisonNotes = string.Join(Environment.NewLine, notes);
        SetSummary(CompareSkippedText, string.Join(" ", notes), _lastComparisonNotes);
        CompareDetail.Text = rows.Length == 0 ? _lastComparisonNotes : "Select a change to inspect the old and new values and the exact difference.";
        CompareExportButton.IsEnabled = !_busy;
        UpdateEmptyStates();
    }

    private async void OnExportComparison(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        if (_lastComparisonRows == null) { ShowStatus("Choose a comparison first", "Compare with the current scan or choose two saved files, then export the result.", true); return; }
        var dialog = new SaveFileDialog { Title = "Export comparison results", Filter = "Text report (*.txt)|*.txt", AddExtension = true, DefaultExt = ".txt" };
        dialog.FileName = "HWID-Comparison-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".txt";
        if (dialog.ShowDialog(this) != true) return;
        SetBusy(true, "Export");
        try
        {
            var lines = new List<string>
            {
                "HWID CHECKER - COMPARISON REPORT",
                _lastComparisonBaseline,
                _lastComparisonCurrent,
                "Summary: " + _lastComparisonSummary,
                "Notes: " + _lastComparisonNotes,
                "",
                "========== Changes =========="
            };
            var number = 0;
            foreach (var row in _lastComparisonRows)
            {
                number++;
                lines.Add($"#{number} / {row.Kind}: {row.Label}");
                if (row.Previous.Length > 0) lines.Add("  OLD: " + row.Previous);
                if (row.Current.Length > 0) lines.Add("  NEW: " + row.Current);
                if (row.Detail.Length > 0) lines.Add("  Detail: " + row.Detail.ReplaceLineEndings(" "));
            }
            lines.Add("");
            lines.Add("This export contains device identifiers; share carefully.");
            await File.WriteAllTextAsync(dialog.FileName, string.Join(Environment.NewLine, lines) + Environment.NewLine, new UTF8Encoding(false));
            ShowStatus("Comparison exported", dialog.FileName + " · The text file contains device IDs.");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { ShowError("Could not export the comparison", ex); }
        finally { SetBusy(false); }
    }
    private void OnComparisonSelected(object sender, SelectionChangedEventArgs e) { CompareDetail.Text = CompareGrid.SelectedItem is ChangeRow row ? row.Label + "\n" + row.Detail : ""; }
    private void OnComparisonDoubleClicked(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is not DependencyObject source ||
            ItemsControl.ContainerFromElement(CompareGrid, source) is not DataGridRow { Item: ChangeRow row }) return;
        if (row.Previous.Length == 0 && row.Current.Length == 0) { ShowStatus("Nothing to copy", "This change has no values on either side."); return; }
        Copy(row.Label + ": " + (row.Previous.Length > 0 ? row.Previous : "(none)") + " → " + (row.Current.Length > 0 ? row.Current : "(none)"));
    }
    private async void OnSave(object sender, RoutedEventArgs e) => await SaveSnapshotAsync();

    private async void OnExportSnapshot(object sender, RoutedEventArgs e)
    {
        if (_snapshot == null || _busy) return;
        var snapshot = _snapshot;
        var settings = ReadSharedLibrary();
        string starting;
        try { starting = EnsureSaveFolder(settings); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { ShowError("Could not open an export folder", ex); return; }
        var picker = new OpenFolderDialog { Title = "Choose where to export the CSV and HTML report", InitialDirectory = starting };
        if (picker.ShowDialog(this) != true) return;
        var stamp = DateTime.Now.ToString("yyyyMMdd-HHmmssfff") + "-" + Guid.NewGuid().ToString("N")[..6];
        var csvPath = Path.Combine(picker.FolderName, "HWID-Export-" + stamp + ".csv");
        var htmlPath = Path.Combine(picker.FolderName, "HWID-Export-" + stamp + ".html");
        SetBusy(true, "Export");
        try
        {
            await Task.Run(() =>
            {
                WriteSnapshotCsv(csvPath, snapshot);
                WriteSnapshotHtmlCore(htmlPath, snapshot);
            });
            ShowStatus("Snapshot exported", Path.GetFileName(csvPath) + " + " + Path.GetFileName(htmlPath) + " in " + picker.FolderName + " · Exports contain device IDs; share carefully.");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { ShowError("Could not export the snapshot", ex); }
        finally { SetBusy(false); }
    }

    private static string CsvField(string value) => "\"" + value.Replace("\"", "\"\"") + "\"";

    private static void WriteSnapshotCsv(string path, DesktopSnapshot snapshot)
    {
        var lines = new List<string> { "Section,Device,Field,Value,Status" };
        foreach (var row in snapshot.Identifiers)
            lines.Add(string.Join(",", CsvField(row.Section), CsvField(row.Device), CsvField(row.Field), CsvField(row.Value), CsvField(row.Status)));
        File.WriteAllLines(path, lines, new UTF8Encoding(false));
    }

    private void WriteSnapshotHtmlCore(string path, DesktopSnapshot snapshot)
    {
        string Encode(string value) => System.Net.WebUtility.HtmlEncode(value)
            .Replace("\r", "").Replace("\n", "<br>");
        var html = new StringBuilder();
        html.Append("<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>HWID Checker report</title><style>");
        html.Append("body{font-family:'Segoe UI',Arial,sans-serif;background:#eef2f7;color:#17222e;margin:24px}");
        html.Append("h1{font-size:22px;margin:0 0 4px}h2{font-size:16px;margin:26px 0 8px;border-bottom:2px solid #c6d2de;padding-bottom:5px}");
        html.Append("table{border-collapse:collapse;width:100%;font-size:13px;margin-bottom:8px}");
        html.Append("th,td{border:1px solid #c6d2de;padding:6px 9px;text-align:left;vertical-align:top}");
        html.Append("th{background:#e8eef4;font-weight:600}tr:nth-child(even) td{background:#f4f7fa}");
        html.Append(".muted{color:#5b6b7c;font-size:12px}");
        html.Append("</style></head><body>");
        html.Append("<h1>HWID Checker \u2014 hardware report</h1>");
        html.Append("<p class='muted'>").Append(Encode(snapshot.Info.Text("Computer"))).Append(" \u00b7 captured ").Append(Encode(J.Date(snapshot.Info.Text("Generated")))).Append(" \u00b7 engine ").Append(Encode(snapshot.Version)).Append(" \u00b7 desktop ").Append(DesktopUpdater.CurrentVersion).Append("</p>");
        foreach (var section in snapshot.Inventory.EnumerateObject())
        {
            var records = section.Value.Rows();
            html.Append("<h2>").Append(Encode(section.Name)).Append(" \u2014 ").Append(records.Length).Append(" record(s)</h2>");
            if (records.Length == 0) { html.Append("<p class='muted'>No records captured.</p>"); continue; }
            html.Append("<table><tr><th style='width:40px'>#</th><th style='width:230px'>Field</th><th>Windows-reported value</th></tr>");
            for (var recordIndex = 0; recordIndex < records.Length; recordIndex++)
            {
                var record = records[recordIndex];
                if (record.ValueKind == JsonValueKind.Object)
                {
                    var first = true;
                    foreach (var field in record.EnumerateObject())
                    {
                        html.Append("<tr><td>").Append(first ? (recordIndex + 1).ToString() : "").Append("</td><td>")
                            .Append(Encode(snapshot.Label(section.Name, field.Name))).Append("</td><td>")
                            .Append(Encode(snapshot.FieldValue(section.Name, recordIndex, field.Name, field.Value))).Append("</td></tr>");
                        first = false;
                    }
                }
                else
                {
                    html.Append("<tr><td>").Append(recordIndex + 1).Append("</td><td>Value</td><td>").Append(Encode(record.Display())).Append("</td></tr>");
                }
            }
            html.Append("</table>");
        }
        html.Append("<p class='muted'>Windows-reported inventory. Values are not guaranteed authentic or unique. This export contains device identifiers; share carefully.</p>");
        html.Append("</body></html>");
        File.WriteAllText(path, html.ToString(), new UTF8Encoding(false));
    }
    private async Task SaveSnapshotAsync()
    {
        if (_snapshot == null || _engine == null || _busy) return;
        var settings = ReadSharedLibrary();
        string starting;
        try { starting = EnsureSaveFolder(settings); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            ShowError("Could not open a save folder", ex);
            return;
        }
        if (settings.Error is { } error)
            ShowStatus("Using the default save folder", starting + " · " + error, true);
        else if (settings.Primary is { } preferred && !SameFolder(preferred, starting))
            ShowStatus("Shared save folder unavailable", "Starting in " + starting, true);
        var picker = new OpenFolderDialog { Title = "Choose where to save the TXT + JSON snapshot", InitialDirectory = starting };
        if (picker.ShowDialog(this) != true) return;
        await SaveToFolderAsync(picker.FolderName);
    }
    private async Task SaveToFolderAsync(string folder)
    {
        if (_snapshot == null || _engine == null || _busy) return;
        SetBusy(true, "Save"); _operationCancellation = new CancellationTokenSource();
        ShowStatus("Saving snapshot", "Creating and verifying a new TXT + JSON report pair.");
        try
        {
            var result = await _engine.ExportAsync(_snapshot.Inventory, folder, _operationCancellation.Token);
            _lastSaveFolder = result.Text("folder"); if (_lastSaveFolder.Length == 0) _lastSaveFolder = folder;
            _additionalFolders.Add(_lastSaveFolder);
            var warning = await RegisterSavedFolderAsync(_lastSaveFolder);
            if (!await RememberPreferencesAsync() && warning == null)
                warning = "Desktop could not remember the last save location.";
            var saved = "TXT + JSON verified in " + _lastSaveFolder;
            ShowStatus("Snapshot saved", warning == null ? saved : warning + " · " + saved, warning != null);
            try { await RefreshSnapshotsAsync().WaitAsync(_operationCancellation.Token); }
            catch (OperationCanceledException) when (_operationCancellation.IsCancellationRequested) { }
        }
        catch (OperationCanceledException) { ShowStatus("Save cancelled", "Check the selected folder before retrying.", true); }
        catch (Exception ex) { ShowError("Snapshot could not be saved", ex); }
        finally { SetBusy(false); _operationCancellation?.Dispose(); _operationCancellation = null; }
    }
    private async Task<string?> RegisterSavedFolderAsync(string folder)
    {
        if (IsVerification && VerificationSharedSettingsPath == null) return null;
        try
        {
            var settings = ReadSharedLibrary();
            if ((settings.Primary is { } primary && SameFolder(primary, folder)) ||
                settings.Folders.Concat(BuiltInReportFolders()).Any(path => SameFolder(path, folder))) return null;
            await SharedSnapshotLibrary.UpdateAsync("add-folder", folder, VerificationSharedSettingsPath);
            return null;
        }
        catch (Exception ex)
        {
            return "Could not add this folder to the shared library. " + ex.Message;
        }
    }

    private void OnOpenReports(object sender, RoutedEventArgs e)
    {
        try
        {
            var folder = SnapshotsGrid.SelectedItem is SnapshotEntry row ? Path.GetDirectoryName(row.Path)! : EnsureSaveFolder(ReadSharedLibrary());
            Process.Start(new ProcessStartInfo(folder) { UseShellExecute = true });
        }
        catch (Exception ex) { ShowError("Could not open the report folder", ex); }
    }
    private void OnOpenConsole(object sender, RoutedEventArgs e)
    {
        if (_engine == null) { ShowStatus("Connect the BAT first", "Use Connect BAT to choose the original checker.", true); return; }
        try
        {
            var directory = Path.GetDirectoryName(_engine.BatPath)!;
            var loader = Path.Combine(directory, "Start-HWID.ps1");
            var runtime = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!Path.GetFileName(_engine.BatPath).Equals("hwid.bat", StringComparison.OrdinalIgnoreCase) || !File.Exists(loader) || !File.Exists(runtime))
            {
                Process.Start(new ProcessStartInfo(_engine.BatPath) { UseShellExecute = true, WorkingDirectory = directory })?.Dispose();
                return;
            }
            var start = new ProcessStartInfo(runtime) { UseShellExecute = false, CreateNoWindow = false, WorkingDirectory = directory };
            foreach (var item in new[] { "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", loader }) start.ArgumentList.Add(item);
            foreach (var name in new[] { "HWID_OWN_CONSOLE", "HWID_CURRENT_WINDOW", "HWID_STARTUP_SIGNAL" }) start.Environment.Remove(name);
            Process.Start(start)?.Dispose();
        }
        catch (Exception ex) { ShowError("Could not open the original console", ex); }
    }
    private void UpdateUpdateButton()
    {
        if (_closing || _updater == null) return;
        UpdatesButton.Content = _updater.Status.State == "restart" ? "Restart required" :
            _updater.IsReady ? "Update ready" : _updater.IsBusy ? "Checking updates…" : "Updates";
        UpdatesButton.ToolTip = _updater.Status.Message;
    }

    private void OnOpenUpdates(object sender, RoutedEventArgs e)
    {
        if (IsVerification || _updater == null) return;
        _updater.RefreshAutomaticPreference();
        UpdateWindow? dialog = null;
        dialog = new UpdateWindow(_updater, EngineVersionText.Text, () => !_busy, () =>
        {
            if (_busy || !_updater.IsReady) return;
            if (_snapshot != null && MessageBox.Show(dialog, "Install the update and restart? Save this scan first if you need to keep it.",
                "HWID Checker", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
            _restartForUpdate = true;
            dialog?.Close();
            Dispatcher.BeginInvoke(new Action(Close));
        }) { Owner = this };
        dialog.ShowDialog();
    }

    private bool PrepareDesktopExit()
    {
        _updater?.Cancel();
        _updater?.RefreshAutomaticPreference();
        if (_updater != null && (_restartForUpdate || _updater.AutomaticEnabled))
        {
            try
            {
                if (_restartForUpdate && !_updater.ScheduleApply(true)) return false;
                if (!_restartForUpdate) _updater.ScheduleApply(false);
            }
            catch (Exception error)
            {
                MessageBox.Show(this, "Could not start the update installer. " + error.Message,
                    "HWID Checker updates", MessageBoxButton.OK, MessageBoxImage.Warning);
                if (_restartForUpdate) return false;
            }
        }
        _updater?.Dispose();
        return true;
    }

    private void OnRestartApp(object sender, RoutedEventArgs e)
    {
        if (_busy) { ShowStatus("Finish the active action", "Cancel or wait for the running scan or report action, then restart.", true); return; }
        if (!IsVerification && _updater != null && _updater.IsReady)
        {
            // A prepared update installs during this close and relaunches the app.
            _restartForUpdate = true;
            Close();
            return;
        }
        _restarting = true;
        RememberPreferencesNow();
        Close();
    }

    private void LaunchRelaunch()
    {
        try
        {
            var exe = Process.GetCurrentProcess().MainModule?.FileName;
            if (!string.IsNullOrWhiteSpace(exe) && File.Exists(exe))
                Process.Start(new ProcessStartInfo(exe) { UseShellExecute = true });
        }
        catch (Exception)
        {
            // A failed relaunch must not block shutdown; the user can start the app normally.
        }
    }

    private async void OnWindowClosing(object? sender, CancelEventArgs e)
    {
        if (_closing) { e.Cancel = _closeCompletion != null; return; }
        if (_busy)
        {
            e.Cancel = true;
            if (_closeRequested) return;
            if (MessageBox.Show(this, "An action is still running. Cancel it and close the app?", "HWID Checker", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
            _closeRequested = true; IsEnabled = false;
            _operationCancellation?.Cancel();
            if (_operationFinished != null)
            {
                // Never let a hung engine freeze the close; bail out after 10 s.
                try { await _operationFinished.Task.WaitAsync(TimeSpan.FromSeconds(10)); } catch (Exception) { }
            }
            if (!PrepareDesktopExit()) { _closeRequested = false; IsEnabled = true; return; }
            RememberPreferencesNow();
            _closing = true; _timer.Stop(); _engine?.Dispose();
            e.Cancel = true;
            BeginWindowFade(() => Close());
            return;
        }
        if (!PrepareDesktopExit()) { e.Cancel = true; return; }
        RememberPreferencesNow();
        _closing = true; _timer.Stop(); _operationCancellation?.Cancel(); _engine?.Dispose();
        e.Cancel = true;
        BeginWindowFade(() => { if (_restarting) LaunchRelaunch(); Close(); });
    }
    private void PrepareLayoutStress()
    {
        var value = string.Concat(Enumerable.Repeat("SYNTHETIC-LONG-DEVICE-IDENTIFIER-", 14));
        var file = Path.Combine(@"C:\Synthetic", value, value, "Snapshot.json");
        ShowStatus("Read provider returned a warning", "The following device could not be read.\n" + value + "\n" + value, true);
        CpuText.Text = value;
        WindowsText.Text = value;
        var rows = Enumerable.Range(1, 24).ToArray();
        switch (_page)
        {
            case "Identifiers":
                IdentifiersGrid.ItemsSource = rows.Select(i => new IdentifierRow("Device inventory", "Hardware ID " + i, value, "Reported", value)).ToArray();
                IdentifiersGrid.SelectedIndex = 0;
                break;
            case "Hardware":
                if (HardwareSectionPicker.IsVisible && HardwareSectionPicker.Items.Count > 1)
                {
                    HardwareSectionPicker.SelectedIndex = 1;
                    if (HardwareSections.SelectedIndex != 1)
                        throw new InvalidOperationException("Dashboard layout: the compact hardware picker did not select its section.");
                }
                using (var record = JsonDocument.Parse(JsonSerializer.Serialize(new { FriendlyName = value, SerialNumber = value })))
                {
                    HardwareRecord.ItemsSource = new[] { new HardwareRecord("1. " + value, record.RootElement.Clone(), 0) };
                    HardwareRecord.SelectedIndex = 0;
                }
                HardwareFields.SelectedIndex = 0;
                break;
            case "Review":
                ReviewGrid.ItemsSource = rows.Select(i => new ReviewRow("Read warning", "Device inventory " + i, value, value)).ToArray();
                ReviewGrid.SelectedIndex = 0;
                break;
            case "Snapshots":
                SnapshotsGrid.ItemsSource = rows.Select(i => new SnapshotEntry(file, $"{i}. {value}.json", "SYNTHETIC-PC", "2026-11-05 13:45", "3.83", "10 KB", DateTimeOffset.UnixEpoch)).ToArray();
                SnapshotsGrid.SelectedIndex = 0;
                SnapshotCountText.Text = $"{rows.Length} synthetic snapshots";
                SetSummary(SnapshotFoldersText, file, file);
                break;
            case "Compare":
                CompareGrid.ItemsSource = rows.Select(i => new ChangeRow("Changed", "Device identifier " + i, value, value + i, value)).ToArray();
                CompareGrid.SelectedIndex = 0;
                SetSummary(CompareBaselineText, "Previous: " + file, file);
                SetSummary(CompareSkippedText, "Coverage warning: " + value);
                break;
        }
        UpdateEmptyStates();
    }

    private void VerifyLayoutStress()
    {
        Rect Bounds(FrameworkElement element) => element.TransformToAncestor(Dashboard).TransformBounds(new Rect(element.RenderSize));

        var overlap = Rect.Intersect(Bounds(HeaderText), Bounds(HeaderActions));
        if ((!overlap.IsEmpty && overlap.Width > 1 && overlap.Height > 1) ||
            StatusDetail.ActualHeight > 25 || PageHost.ActualHeight < 140 ||
            Bounds(PageHost).Bottom > Dashboard.ActualHeight)
        {
            throw new InvalidOperationException("Dashboard layout: header, status, or page bounds conflict.");
        }

        var table = _page switch
        {
            "Identifiers" => IdentifiersGrid,
            "Hardware" => HardwareFields,
            "Review" => ReviewGrid,
            "Snapshots" => SnapshotsGrid,
            "Compare" => CompareGrid,
            _ => ScanGrid
        };
        if (table.ActualHeight < 80 || table.ActualWidth < 200)
            throw new InvalidOperationException($"Dashboard layout: the {_page} table only has {table.ActualWidth:0} × {table.ActualHeight:0} DIPs.");

        if (_page == "Hardware" && (HardwareRecord.ActualHeight > 43 || HardwareRecord.SelectedItem is not HwidDesktop.HardwareRecord))
            throw new InvalidOperationException("Dashboard layout: the hardware picker is oversized or lost its record.");
    }

    private Task WriteTestResultAsync(string path, bool success) => File.WriteAllTextAsync(path, JsonSerializer.Serialize(new
    {
        success, desktopVersion = DesktopUpdater.CurrentVersion, engineVersion = _snapshot?.Version, engineConnected = _engine != null,
        sectionsRead = _snapshot?.SectionsRead ?? 0, identifierFields = _snapshot?.ReportedIds ?? 0,
        knownDeviceRecords = _snapshot?.DeviceCount ?? 0, findings = _snapshot?.Findings.Count ?? 0,
        responsiveTicks = _responsiveTicks, busy = _busy, page = _page,
        scanRows = ScanRows.Count, hardwareSections = HardwareSections.Items.Count,
        identifiersDisplayed = IdentifiersGrid.Items.Count, hardwareIdentifiersSaved = false,
        contentWidth = Dashboard.ActualWidth, contentHeight = Dashboard.ActualHeight,
        layoutDpi = VisualTreeHelper.GetDpi(Dashboard).PixelsPerInchX,
        layoutStress = _args.Contains("--layout-stress", StringComparer.OrdinalIgnoreCase)
    }, new JsonSerializerOptions { WriteIndented = true }));

    private async Task VerifyReadabilityAsync(string resultPath)
    {
        if (!IsVerification || _snapshot == null) throw new InvalidOperationException("A synthetic fixture is required.");
        var original = _snapshot;
        var originalSection = (HardwareSections.SelectedItem as HardwareSection)?.Name;
        var originalWidth = Width;
        var originalHeight = Height;
        var originalPage = _page;
        var checks = new List<string>();
        void Check(bool condition, string name)
        {
            if (!condition) throw new InvalidOperationException("Dashboard layout: readability: " + name);
            checks.Add(name);
        }
        async Task SettleAsync()
        {
            await Task.Delay(180);
            await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            UpdateLayout();
        }
        async Task CaptureAsync(string name)
        {
            await SettleAsync();
            var surface = (FrameworkElement)Content;
            var image = new RenderTargetBitmap((int)Math.Ceiling(surface.ActualWidth), (int)Math.Ceiling(surface.ActualHeight), 96, 96, PixelFormats.Pbgra32);
            image.Render(surface);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(image));
            using var stream = File.Create(Path.Combine(Path.GetDirectoryName(resultPath)!, name + ".png"));
            encoder.Save(stream);
        }
        HardwareSection Section(string name) => HardwareSections.Items.Cast<HardwareSection>().First(section => section.Name == name);
        try
        {
            Check(FontFamily.Source == "Segoe UI" && FontSize == 14 &&
                TextOptions.GetTextFormattingMode(this) == TextFormattingMode.Display, "the default body uses readable Segoe UI at 14 DIPs");
            var header = new System.Windows.Controls.Primitives.DataGridColumnHeader { Style = (Style)FindResource(typeof(System.Windows.Controls.Primitives.DataGridColumnHeader)) };
            var cell = new TextBlock { Style = (Style)FindResource("CellText") };
            Check(cell.FontSize == 14 && cell.FontWeight == FontWeights.Normal && header.FontSize >= 13 &&
                header.FontWeight == FontWeights.Normal, "table values and headers avoid tiny or bold text");
            Check(HardwareSections.SelectedItem is HardwareSection selected && selected.Name == "System hardware" &&
                HardwareRecord.SelectedItem is HardwareRecord selectedRecord && selectedRecord.Data.Text("Model").Length > 0,
                "the initial hardware view opens captured PC hardware");
            Check(Section("System hardware").CountText == "1 record" && HardwareCountText.Text == "1 record" &&
                Section("Report info").Display.Contains("entry"),
                "section counts include clear singular units");
            Width = Math.Min(1260, SystemParameters.WorkArea.Width - 16);
            Height = Math.Min(850, SystemParameters.WorkArea.Height - 16);
            Navigate("Hardware");
            await SettleAsync();
            var sectionTemplate = (StackPanel)HardwareSections.ItemTemplate.LoadContent();
            Check(sectionTemplate.Children.OfType<TextBlock>().First().TextWrapping == TextWrapping.Wrap &&
                sectionTemplate.Children.OfType<TextBlock>().Count() == 2, "wide section names wrap with a separate readable count");
            Check(HardwareRecord.SelectedItem is HardwareRecord named && named.Title != "Record" && named.Title != "Record 1",
                "the selected hardware record has a descriptive title");
            await CaptureAsync("hardware-default");

            HardwareSections.SelectedItem = Section("Report info");
            var rawDate = original.Info.Text("Generated");
            var captured = HardwareFields.Items.Cast<FieldRow>().First(field => field.RawValue == rawDate);
            HardwareFields.SelectedItem = captured;
            Check(captured.Field == "Captured at" && captured.Value != rawDate &&
                HardwareRecord.SelectedItem is HardwareRecord metadata && metadata.Title == "Snapshot details",
                "advanced capture details use readable labels and timestamps");
            var access = HardwareFields.Items.Cast<FieldRow>().First(field => field.Field == "Access level");
            Check(access.Value == (original.Info.Flag("Administrator") ? "Administrator" : "Standard user") &&
                access.RawValue == original.Info.Text("Administrator"), "access level explains legacy boolean metadata and preserves the original");
            Check(HardwareDetail.Text.Contains("Original value") && HardwareDetail.Text.Contains(rawDate),
                "formatted metadata retains the full original value in details");
            await CaptureAsync("hardware-capture-details");
            HardwareSections.SelectedItem = Section("CPU");
            var rawId = original.First("CPU", "ProcessorId");
            var identifier = HardwareFields.Items.Cast<FieldRow>().First(field => field.RawValue == rawId);
            HardwareFields.SelectedItem = identifier;
            Check(identifier.Value == rawId && HardwareDetail.Text.Contains(rawId) &&
                HardwareDetail.FontFamily.Source == "Consolas", "exact identifiers remain available in a monospaced detail view");
            ApplySnapshot(new DesktopSnapshot(original.Data));
            Check(HardwareSections.SelectedItem is HardwareSection retained && retained.Name == "CPU",
                "a refreshed snapshot retains an explicitly selected hardware section");

            var catalog = System.Text.Json.Nodes.JsonNode.Parse(original.Data.GetRawText())!;
            foreach (var section in ScanSectionNames.Where(name => name != "All-known device catalog"))
                catalog["inventory"]![section] = new System.Text.Json.Nodes.JsonArray(new System.Text.Json.Nodes.JsonObject { ["Unavailable"] = "Synthetic unavailable section" });
            catalog["inventory"]!["Extended device inventory"] = new System.Text.Json.Nodes.JsonArray(
                new System.Text.Json.Nodes.JsonObject { ["Name"] = "Synthetic readable device", ["DeviceInstanceId"] = "ROOT\\SYNTHETIC" });
            HardwareSections.SelectedIndex = -1;
            using (var document = JsonDocument.Parse(catalog.ToJsonString()))
                ApplySnapshot(new DesktopSnapshot(document.RootElement));
            Check(HardwareSections.SelectedItem is HardwareSection available && available.Name == "Extended device inventory",
                "catalog-only captures default to readable device data");
            ApplySnapshot(original);
            HardwareSections.SelectedItem = Section("System hardware");
            Width = 640;
            Height = 480;
            await SettleAsync();
            VerifyLayoutStress();
            Check(HardwareSectionPicker.IsVisible && HardwareFields.ActualHeight >= 80 && HardwareFields.FontSize == 14,
                "compact hardware keeps readable values and working section controls");
            await CaptureAsync("hardware-compact");
            Width = 840;
            Height = 560;
            await SettleAsync();
            VerifyLayoutStress();
            Check(HardwareFields.ActualHeight >= 80 && HardwareFields.FontSize == 14,
                "reduced logical space retains the body size and visible table");
            await CaptureAsync("hardware-reduced-space");
            await File.WriteAllTextAsync(resultPath, JsonSerializer.Serialize(new
            {
                success = true, checks = checks.Count, names = checks, syntheticOnly = true, hardwareIdentifiersSaved = false
            }, new JsonSerializerOptions { WriteIndented = true }));
        }
        finally
        {
            Width = originalWidth;
            Height = originalHeight;
            ApplySnapshot(original);
            HardwareSections.SelectedItem = HardwareSections.Items.Cast<HardwareSection>().FirstOrDefault(section => section.Name == originalSection);
            Navigate(originalPage);
            await SettleAsync();
        }
    }

    private async Task VerifyUiRegressionAsync(string resultPath)
    {
        if (!IsVerification || _snapshot == null) throw new InvalidOperationException("A synthetic fixture is required.");
        var original = _snapshot;
        var previousPage = _page;
        var motion = ReadLocalValue(UiMotion.EnabledProperty);
        var checks = new List<string>();
        void Check(bool condition, string name)
        {
            if (!condition) throw new InvalidOperationException("Dashboard layout: UI regression: " + name);
            checks.Add(name);
        }
        async Task SettleAsync()
        {
            await Task.Delay(180);
            await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            UpdateLayout();
        }
        var directory = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(resultPath))!, "ui-fixtures-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        async Task CaptureEmptyStateAsync(string name, ScrollViewer panel)
        {
            await SettleAsync();
            var bounds = panel.TransformToAncestor(PageHost).TransformBounds(new Rect(panel.RenderSize));
            var surface = (FrameworkElement)Content;
            var image = new RenderTargetBitmap((int)Math.Ceiling(surface.ActualWidth), (int)Math.Ceiling(surface.ActualHeight), 96, 96, PixelFormats.Pbgra32);
            image.Render(surface);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(image));
            using var stream = File.Create(Path.Combine(Path.GetDirectoryName(resultPath)!, name + ".png"));
            encoder.Save(stream);
            Check(panel.ActualWidth >= 200 && panel.ActualHeight >= 80 && bounds.Bottom <= PageHost.ActualHeight + 1 &&
                bounds.Top >= -1 && panel.ScrollableHeight < 1,
                $"empty-state message and action fit {name} ({panel.ActualWidth:0} x {panel.ActualHeight:0}, scroll {panel.ScrollableHeight:0})");
        }
        try
        {
            _snapshot = null;
            FilterReview();
            UpdateButtons();
            ShowStatus("Ready to scan", "Choose Scan this PC to read hardware information.");
            Navigate("Review");
            Check(ReviewEmptyState.Visibility == Visibility.Visible && ReviewGrid.Visibility == Visibility.Collapsed &&
                (string?)ReviewEmptyAction.Tag == "Scan" && ReviewEmptyAction.IsEnabled,
                "review before a scan explains its next action");
            await CaptureEmptyStateAsync("review-before-scan", ReviewEmptyState);
            Navigate("Compare");
            Check(CompareEmptyState.Visibility == Visibility.Visible && CompareFilesButton.IsEnabled && !CompareCurrentButton.IsEnabled,
                "comparison before a scan offers two saved files");
            await CaptureEmptyStateAsync("compare-before-scan", CompareEmptyState);
            SetBusy(true, "Scan");
            Navigate("Review");
            Check(ReviewEmptyTitle.Text.Contains("progress") && (string?)ReviewEmptyAction.Tag == "Overview",
                "review during the first scan explains the waiting state");
            await CaptureEmptyStateAsync("review-scanning", ReviewEmptyState);
            Navigate("Compare");
            Check(CompareEmptyTitle.Text.Contains("running") && (string?)CompareEmptyAction.Tag == "Overview" && CompareEmptyAction.IsEnabled,
                "comparison during a scan points to progress");
            SetBusy(false);

            var clean = System.Text.Json.Nodes.JsonNode.Parse(original.Data.GetRawText())!;
            clean["review"] = new System.Text.Json.Nodes.JsonObject();
            using (var cleanDocument = JsonDocument.Parse(clean.ToJsonString()))
                ApplySnapshot(new DesktopSnapshot(cleanDocument.RootElement));
            Navigate("Review");
            ShowStatus("Scan complete", "No review items were reported for this synthetic capture.");
            Check(ReviewEmptyTitle.Text == "No review items reported" && (string?)ReviewEmptyAction.Tag == "Hardware",
                "a completed scan without findings is distinguished from an unscanned PC");
            await CaptureEmptyStateAsync("review-no-findings", ReviewEmptyState);
            ApplySnapshot(original);
            ShowStatus("Scan complete", "Review explains the items reported for this synthetic capture.");
            ReviewSearch.Text = "no-matching-review-fixture";
            Check(ReviewEmptyTitle.Text.Contains("match") && (string?)ReviewEmptyAction.Tag == "ClearReview",
                "filtered review results explain how to restore findings");
            await CaptureEmptyStateAsync("review-filter-empty", ReviewEmptyState);
            OnEmptyStateAction(ReviewEmptyAction, new RoutedEventArgs());
            Check(ReviewSearch.Text.Length == 0 && ReviewGrid.Items.Count > 0, "the empty-review action clears the filter");

            using (var unchanged = JsonDocument.Parse("""{"changes":[],"previousCount":2,"currentCount":2,"skippedFields":0,"skippedSections":[],"scopeWarnings":[]}"""))
                RenderComparison(unchanged.RootElement, "older-synthetic.json", true);
            Navigate("Compare");
            ShowStatus("Comparison complete", _lastComparisonSummary);
            Check(CompareEmptyTitle.Text.Contains("No changes") && CompareExportButton.IsEnabled && CompareDetail.Text.Contains("Identifier fields"),
                "an unchanged comparison explains the result and can be exported");
            await CaptureEmptyStateAsync("compare-unchanged", CompareEmptyState);
            using (var sameFile = JsonDocument.Parse("""{"changes":[],"previousCount":2,"currentCount":2,"skippedFields":0,"skippedSections":[],"scopeWarnings":[]}"""))
                RenderComparison(sameFile.RootElement, "same-synthetic.json", false, "same-synthetic.json");
            ShowStatus("Comparison complete", _lastComparisonSummary, true);
            Check(CompareEmptyTitle.Text.Contains("same file") && CompareDetail.Text.Contains("same JSON file"),
                "self-comparison identifies the same selected file without claiming a separate capture");
            await CaptureEmptyStateAsync("compare-same-file", CompareEmptyState);
            using (var incomparable = JsonDocument.Parse("""{"changes":[],"previousCount":0,"currentCount":0,"skippedFields":3,"skippedSections":["BIOS"],"scopeWarnings":[]}"""))
                RenderComparison(incomparable.RootElement, "older-synthetic.json", true);
            ShowStatus("Comparison finished", _lastComparisonSummary, true);
            Check(CompareEmptyTitle.Text.Contains("No identifier fields") && CompareDetail.Text.Contains("BIOS"),
                "a non-comparable capture explains skipped data instead of claiming unchanged IDs");
            await CaptureEmptyStateAsync("compare-no-comparable-fields", CompareEmptyState);
            using (var oneSided = JsonDocument.Parse("""{"changes":[],"previousCount":0,"currentCount":2,"skippedFields":2,"skippedSections":[],"scopeWarnings":[]}"""))
                RenderComparison(oneSided.RootElement, "older-synthetic.json", true);
            Check(CompareEmptyTitle.Text.Contains("No identifier fields") && !CompareEmptyText.Text.Contains("match"),
                "one-sided available values do not claim that compared IDs match");
            await CaptureEmptyStateAsync("compare-one-sided-values", CompareEmptyState);
            using (var added = JsonDocument.Parse("""{"changes":[{"kind":"Current only","section":"CPU","field":"ProcessorId","device":"SYNTHETIC-DEVICE","previous":null,"current":"SYNTHETIC-ID","difference":""}],"previousCount":0,"currentCount":1,"skippedFields":0,"skippedSections":[],"scopeWarnings":[]}"""))
                RenderComparison(added.RootElement, "older-synthetic.json", true);
            Check(CompareGrid.Visibility == Visibility.Visible && CompareEmptyState.Visibility == Visibility.Collapsed &&
                _lastComparisonSummary.Contains("1 only in newer capture"), "one-sided added values remain visible as reported changes");
            ApplySnapshot(original);
            SetBusy(true, "Compare");
            Check(CompareEmptyTitle.Text == "Comparing snapshots" && CompareEmptyAction.Visibility == Visibility.Collapsed,
                "an active comparison replaces the empty table with progress");
            SetBusy(false);
            SetBusy(true, "Scan");
            var beforeStale = ScanRows.ToArray();
            var oldGeneration = _scanGeneration++;
            var staleUpdate = new BridgeProgress("CPU", "CPU", 9, 18, "READ", 8, "Synthetic stale progress");
            ApplyScanProgress(staleUpdate, oldGeneration);
            Check(ScanRows.SequenceEqual(beforeStale), "progress from an earlier scan cannot overwrite a new scan");
            _operationCancellation = new CancellationTokenSource();
            _operationCancellation.Cancel();
            ApplyScanProgress(staleUpdate, _scanGeneration);
            Check(ScanRows.SequenceEqual(beforeStale), "progress received after cancellation cannot replace the cancelling state");
            _operationCancellation.Dispose();
            _operationCancellation = null;
            ApplyScanProgress(staleUpdate, _scanGeneration);
            Check(_scanCompletedStages == 9 && _scanTotalStages == 18, "progress counts use the scanner's actual stage total");
            const string nextStep = "Retry with the required Windows access.";
            ApplyScanProgress(new BridgeProgress("CPU", "CPU", 9, 19, "NOT READ", 0, "Windows could not read this section.",
                FailureCode: "READ-01", NextStep: nextStep), _scanGeneration);
            var diagnosticsPresent = ScanRows.First(row => row.Name == "CPU").Detail.Contains("READ-01") &&
                ScanRows.First(row => row.Name == "CPU").Detail.Contains(nextStep);
            var completeMessage = "READ-01 · " + nextStep;
            ApplyScanProgress(new BridgeProgress("CPU", "CPU", 9, 19, "NOT READ", 0, completeMessage,
                FailureCode: "READ-01", NextStep: nextStep), _scanGeneration);
            Check(diagnosticsPresent && ScanRows.First(row => row.Name == "CPU").Detail == completeMessage,
                "scan detail keeps actionable diagnostics without repeating existing guidance");
            SetBusy(false);
            ApplySnapshot(original);
            var data = System.Text.Json.Nodes.JsonNode.Parse(original.Data.GetRawText())!;
            data["inventory"]!["UI scalar fixture"] = new System.Text.Json.Nodes.JsonArray(
                "MATCH scalar", 42, true, null,
                System.Text.Json.Nodes.JsonNode.Parse("""{"Name":"Object record","Aliases":["MATCH nested"]}"""));
            using (var document = JsonDocument.Parse(data.ToJsonString()))
                ApplySnapshot(new DesktopSnapshot(document.RootElement));
            Navigate("Hardware");
            HardwareSections.SelectedItem = HardwareSections.Items.Cast<HardwareSection>().First(section => section.Name == "UI scalar fixture");
            HardwareSearch.Text = "MATCH";
            Check(HardwareRecord.Items.Count == 2, "hardware search matches scalar and nested array values");
            HardwareSearch.Text = "42";
            Check(HardwareRecord.Items.Count == 1, "hardware search accepts numeric records");
            HardwareSearch.Text = "true";
            Check(HardwareRecord.Items.Count == 1, "hardware search accepts boolean records");
            HardwareSearch.Text = "absent-ui-record";
            Check(HardwareRecord.Items.Count == 0 && HardwareDetail.Text.Contains("No records"), "empty hardware search clears old details");
            HardwareSearch.Clear();
            ApplySnapshot(original);
            var originalActivity = ScanRows.ToArray();

            foreach (var page in new[] { "Identifiers", "Hardware", "Snapshots", "Review", "Identifiers" }) Navigate(page);
            await SettleAsync();
            Check(PageHost.Children.OfType<FrameworkElement>().Count(page => page.Visibility == Visibility.Visible) == 1 &&
                IdentifiersPage.Visibility == Visibility.Visible, "rapid navigation ends on the last requested page");
            Check(PageHost.Children.OfType<FrameworkElement>().All(page => page.Opacity == 1 &&
                !DependencyPropertyHelper.GetValueSource(page, OpacityProperty).IsAnimated &&
                (page.RenderTransform is not TranslateTransform slide || slide.Y == 0 && !slide.HasAnimatedProperties)),
                "interrupted navigation restores opacity and transforms");
            IdSearch.Focus();
            Navigate("Identifiers");
            await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            Check(Keyboard.FocusedElement == IdSearch, "reopening the active page preserves search focus");
            IdentifiersGrid.SelectedIndex = 0;
            var status = StatusTitle.Text;
            OnIdDoubleClicked(IdentifiersGrid, new MouseButtonEventArgs(Mouse.PrimaryDevice, Environment.TickCount, MouseButton.Left)
                { RoutedEvent = Control.MouseDoubleClickEvent, Source = IdentifiersGrid });
            Check(StatusTitle.Text == status, "blank identifier double-click does not copy the previous selection");
            CompareGrid.ItemsSource = new[] { new ChangeRow("Changed", "Synthetic field", "OLD-SYNTHETIC", "NEW-SYNTHETIC", "") };
            CompareGrid.SelectedIndex = 0;
            OnComparisonDoubleClicked(CompareGrid, new MouseButtonEventArgs(Mouse.PrimaryDevice, Environment.TickCount, MouseButton.Left)
                { RoutedEvent = Control.MouseDoubleClickEvent, Source = CompareGrid });
            Check(StatusTitle.Text == status, "blank comparison double-click does not copy the previous selection");

            Navigate("Overview");
            SetBusy(true, "Scan");
            ScanRows.Clear();
            foreach (var name in ScanSectionNames) ScanRows.Add(new(name, "WAITING", "—", "Synthetic waiting", ""));
            await SettleAsync();
            OverviewPage.ScrollToTop();
            await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            var offset = OverviewPage.VerticalOffset;
            var update = new BridgeProgress("Extended device inventory", "Extended device inventory", 18, 19, "READING", 0, "Synthetic heartbeat");
            ApplyScanProgress(update);
            await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            ApplyScanProgress(update);
            await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            Check(Math.Abs(OverviewPage.VerticalOffset - offset) < 1, "scan heartbeats preserve manual scroll position");
            SetBusy(false);
            RestoreScanActivity();
            var restored = ScanRows.ToArray();
            ApplyScanProgress(update);
            Check(ScanRows.SequenceEqual(restored), "late progress cannot change a completed or cancelled display");
            Check(ScanRows.SequenceEqual(originalActivity), "older snapshots restore their original activity coverage");

            var first = Path.Combine(directory, "first.json");
            await File.WriteAllTextAsync(first, original.Inventory.GetRawText());
            _additionalFolders.Add(directory);
            Navigate("Snapshots");
            await RefreshSnapshotsAsync();
            SnapshotsGrid.SelectedItem = SnapshotsGrid.Items.Cast<SnapshotEntry>().First(entry => entry.Path == first);
            await File.WriteAllTextAsync(Path.Combine(directory, "second.json"), original.Inventory.GetRawText());
            await RefreshSnapshotsAsync();
            Check(SnapshotsGrid.SelectedItem is SnapshotEntry selected && selected.Path == first, "snapshot refresh preserves selection by file path");
            await SettleAsync();
            Check(SnapshotsGrid.Opacity == 1 && !DependencyPropertyHelper.GetValueSource(SnapshotsGrid, OpacityProperty).IsAnimated,
                "snapshot refresh finishes without retaining a fade clock");

            FadeIn(Dashboard, 0.9, 500);
            FadeIn(SnapshotsGrid, 0.9, 500);
            Navigate("Hardware");
            UiMotion.SetEnabled(this, false);
            Check(Dashboard.Opacity == 1 && SnapshotsGrid.Opacity == 1 && _fadeClocks.Count == 0,
                "reducing motion immediately clears running fades");
            Navigate("Review");
            Check(!DependencyPropertyHelper.GetValueSource(ReviewPage, OpacityProperty).IsAnimated &&
                (ReviewPage.RenderTransform is not TranslateTransform reducedSlide || reducedSlide.Y == 0),
                "reduced motion changes pages without animation");
            HardwareRecord.ApplyTemplate();
            var popup = (System.Windows.Controls.Primitives.Popup)HardwareRecord.Template.FindName("PART_Popup", HardwareRecord);
            Check(!UiMotion.GetEnabled(ScanButton) && popup.PopupAnimation == System.Windows.Controls.Primitives.PopupAnimation.None,
                "reduced motion propagates to buttons and dropdowns");
            var completions = 0;
            BeginWindowFade(() => completions++);
            FinishWindowFade();
            await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            Check(completions == 1, "close completion executes once when motion is disabled");
            IsEnabled = true;
            UiMotion.SetEnabled(this, true);
            var interruptedClose = 0;
            BeginWindowFade(() => interruptedClose++);
            await Task.Delay(35);
            Check(DependencyPropertyHelper.GetValueSource(this, OpacityProperty).IsAnimated,
                "animated close starts its fade clock");
            UiMotion.SetEnabled(this, false);
            await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            Check(interruptedClose == 1 && Opacity == 1 && !DependencyPropertyHelper.GetValueSource(this, OpacityProperty).IsAnimated,
                "reducing motion during close finishes once and clears the clock");
            IsEnabled = true;
            UiMotion.SetEnabled(this, true);
            var animatedClose = 0;
            BeginWindowFade(() => animatedClose++);
            await SettleAsync();
            Check(animatedClose == 1 && !DependencyPropertyHelper.GetValueSource(this, OpacityProperty).IsAnimated,
                "animated close completes once and releases its clock");
            IsEnabled = true;
            await File.WriteAllTextAsync(resultPath, JsonSerializer.Serialize(new
            {
                success = true, checks = checks.Count, names = checks, syntheticOnly = true,
                hardwareIdentifiersSaved = false
            }, new JsonSerializerOptions { WriteIndented = true }));
        }
        finally
        {
            SetBusy(false);
            _additionalFolders.Remove(directory);
            HardwareSearch.Clear();
            if (motion == DependencyProperty.UnsetValue) ClearValue(UiMotion.EnabledProperty);
            else SetValue(UiMotion.EnabledProperty, motion);
            ApplySnapshot(original);
            Navigate(previousPage);
            IsEnabled = true;
        }
    }

    private async Task VerifyWorkflowAsync(string resultPath)
    {
        if (_snapshot == null || _engine == null) throw new InvalidOperationException("A synthetic fixture and BAT connection are required for workflow verification.");
        var checks = 0;
        void Check(bool value, string description) { if (!value) throw new InvalidOperationException("Desktop workflow: " + description); checks++; }
        var directory = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(resultPath))!, "test-output-workflow-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var sharedSettingsPath = VerificationSharedSettingsPath;
        var original = _snapshot;
        IdSearch.Text = "CPU"; Check(IdentifiersGrid.Items.Count > 0, "ID search finds matching fields");
        IdentifiersGrid.SelectedIndex = 0; Check(IdDetail.Text.Length > 0, "selected ID exposes full value");
        IdSearch.Text = "no-matching-hwid-field-123456"; Check(IdentifiersGrid.Items.Count == 0 && IdDetail.Text.Length == 0, "empty filter clears stale selected ID");
        IdSearch.Clear(); Check(IdentifiersGrid.Items.Count == original.Identifiers.Count, "clearing search restores exact ID rows");
        IdentifiersGrid.SelectedIndex = 0;
        ReviewGrid.SelectedIndex = 0;
        ApplySnapshot(new DesktopSnapshot(original.Data));
        Check(ReviewGrid.SelectedIndex == -1 && IdentifiersGrid.SelectedIndex == -1 && ReviewDetail.Text.Length == 0 && IdDetail.Text.Length == 0,
            "new snapshot clears stale finding and ID selections and details");
        HardwareSections.SelectedItem = HardwareSections.Items.Cast<HardwareSection>().First(section => section.Name == "Report info");
        var rescanned = System.Text.Json.Nodes.JsonNode.Parse(original.Data.GetRawText())!;
        rescanned["inventory"]!["Report info"]!["Computer"] = "SYNTHETIC-RESCAN";
        using (var data = JsonDocument.Parse(rescanned.ToJsonString()))
        {
            ApplySnapshot(new DesktopSnapshot(data.RootElement));
            Check(HardwareRecord.SelectedItem is HardwareRecord record && record.Data.Text("Computer") == "SYNTHETIC-RESCAN" &&
                ComputerText.Text == "SYNTHETIC-RESCAN" && CapturedText.Text.StartsWith("Captured", StringComparison.Ordinal),
                "rescan refreshes hardware records when section names and counts match");
        }
        ApplySnapshot(original);
        HardwareSections.SelectedItem = HardwareSections.Items.Cast<HardwareSection>().First(x => x.Name == "Memory modules");
        var clock = HardwareFields.Items.Cast<FieldRow>().FirstOrDefault(x => x.Field.Contains("Configured", StringComparison.OrdinalIgnoreCase));
        Check(clock != null && clock.Value.Contains("Unknown", StringComparison.OrdinalIgnoreCase), "memory-clock zero uses BAT display semantics");
        var primaryFolder = Path.Combine(Path.GetDirectoryName(_engine.BatPath)!, "HWID-Reports");
        Directory.CreateDirectory(primaryFolder);
        var primaryFile = Path.Combine(primaryFolder, "HWID-DESKTOP-TEST-" + Guid.NewGuid().ToString("N") + ".json");
        try
        {
            await File.WriteAllTextAsync(primaryFile, original.Inventory.GetRawText());
            var saveFolder = Path.Combine(directory, "saved snapshots & Unicode é");
            await SaveToFolderAsync(saveFolder);
            Check(StatusTitle.Text == "Snapshot saved", "desktop save completed");
            Check(Directory.GetFiles(saveFolder, "*.json").Length == 1 && Directory.GetFiles(saveFolder, "*.txt").Length == 1, "verified TXT and JSON pair exists");
            Check(ReportFolders().Contains(primaryFolder, StringComparer.OrdinalIgnoreCase), "custom save retains primary reports folder");
            Check(SnapshotsGrid.Items.Cast<SnapshotEntry>().Any(x => x.Path == primaryFile), "older primary snapshot stays visible after custom save");
            Check(SnapshotsGrid.Items.Cast<SnapshotEntry>().Any(x => Path.GetDirectoryName(x.Path) == saveFolder), "newly saved snapshot is detected immediately");
            if (sharedSettingsPath != null)
                Check(ReadSharedLibrary().Folders.Contains(saveFolder, StringComparer.OrdinalIgnoreCase),
                    "a successful Desktop save adds its custom folder to the shared library");
            var extra = Path.Combine(directory, "another folder"); Directory.CreateDirectory(extra);
            var extraFile = Path.Combine(extra, "renamed-older-capture.json"); await File.WriteAllTextAsync(extraFile, original.Inventory.GetRawText());
            var firstRefresh = RefreshSnapshotsAsync();
            if (sharedSettingsPath != null)
                await SharedSnapshotLibrary.UpdateAsync("add-folder", extra, sharedSettingsPath);
            else
                _additionalFolders.Add(extra);
            var secondRefresh = RefreshSnapshotsAsync();
            await Task.WhenAll(firstRefresh, secondRefresh);
            Check(SnapshotsGrid.Items.Cast<SnapshotEntry>().Any(x => x.Path == extraFile), "folder added during refresh is included before completion");
            var preferencesFile = Path.Combine(directory, "preferences.json");
            Check(await RememberPreferencesAsync(preferencesFile), "snapshot folder preferences are saved");
            Check(!File.ReadAllText(preferencesFile).Contains("CPU-000123"), "settings retain paths without scanned identifier values");
            _lastSaveFolder = ""; _additionalFolders.Clear(); LoadPreferences(preferencesFile); await RefreshSnapshotsAsync();
            Check(_lastSaveFolder == saveFolder && SnapshotsGrid.Items.Cast<SnapshotEntry>().Any(x => x.Path == extraFile), "custom snapshot locations are rediscovered after preference reload");
            if (sharedSettingsPath != null)
            {
                await SharedSnapshotLibrary.UpdateAsync("remove-folder", extra, sharedSettingsPath);
                await RefreshSnapshotsAsync();
                Check(!SnapshotsGrid.Items.Cast<SnapshotEntry>().Any(x => x.Path == extraFile) && File.Exists(extraFile),
                    "unwatching a shared folder updates the Desktop list and preserves the snapshot");
            }
            var previous = System.Text.Json.Nodes.JsonNode.Parse(original.Inventory.GetRawText())!;
            previous["CPU"]![0]!["ProcessorId"] = "CPU-CHANGED-001";
            var previousPath = Path.Combine(directory, "previous IDs.json"); await File.WriteAllTextAsync(previousPath, previous.ToJsonString());
            await CompareAsync(previousPath);
            Check(CompareGrid.Items.Cast<ChangeRow>().Any(x => x.Kind == "Changed" && x.Previous == "CPU-CHANGED-001" && x.Current == "CPU-000123"), "comparison shows exact previous and current CPU IDs");
            CompareGrid.SelectedIndex = 0;
            Check(CompareDetail.Text.Contains("OLD:") && CompareDetail.Text.Contains("NEW:"), "change detail exposes both full values");
            ApplySnapshot(new DesktopSnapshot(original.Data));
            Check(CompareGrid.Items.Count == 0 && CompareBaselineText.Text == "Baseline not selected" && CompareDetail.Text.Length == 0, "new snapshot invalidates old current-scan comparison");
            await CompareAsync(previousPath);
            Check(!_busy && _operationCancellation == null && _operationFinished?.Task.IsCompleted == true, "operation state and completion signal are released");
            var completed = _snapshot;
            var previousActivity = ScanRows.ToArray();
            var attempt = RunScanAsync();
            var preparedDisplay = ScanRows.Count == 19 && ScanRows.All(row => row.Status == "WAITING" && row.Records == "—") &&
                MetricsGrid.Visibility == Visibility.Collapsed && OverviewComputerCard.Visibility == Visibility.Collapsed;
            await Task.Delay(1500); _operationCancellation?.Cancel(); await attempt;
            Check(preparedDisplay && ReferenceEquals(_snapshot, completed) && StatusTitle.Text == "Scan cancelled" &&
                ScanElapsedText.Text.StartsWith("Last attempt"),
                "scan starts with waiting rows and cancellation retains the last completed snapshot");
            Check(ScanRows.SequenceEqual(previousActivity), "cancelled rescan restores all previous activity rows");
            await CompareAsync(previousPath); CompareGrid.SelectedIndex = 0;
            await File.WriteAllTextAsync(resultPath, JsonSerializer.Serialize(new { success = true, checks, hardwareIdentifiersSaved = false, syntheticOnly = true }, new JsonSerializerOptions { WriteIndented = true }));
        }
        finally { if (File.Exists(primaryFile)) File.Delete(primaryFile); }
    }
}

internal sealed class UiCommand(Func<Task> execute, Func<bool> canExecute) : ICommand
{
    public bool CanExecute(object? parameter) => canExecute();
    public async void Execute(object? parameter) => await execute();
    public event EventHandler? CanExecuteChanged { add => CommandManager.RequerySuggested += value; remove => CommandManager.RequerySuggested -= value; }
}

public static class UiMotion
{
    public static readonly DependencyProperty EnabledProperty = DependencyProperty.RegisterAttached(
        "Enabled", typeof(bool), typeof(UiMotion), new FrameworkPropertyMetadata(true, FrameworkPropertyMetadataOptions.Inherits));

    public static bool GetEnabled(DependencyObject element) => (bool)element.GetValue(EnabledProperty);
    public static void SetEnabled(DependencyObject element, bool value) => element.SetValue(EnabledProperty, value);
}
