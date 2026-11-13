using System.Windows;
using System.Windows.Controls;

namespace HwidDesktop;

internal enum UiStatusKind { Info, Working, Success, Review, Error }

public partial class MainWindow
{
    private void ApplyStatusKind(UiStatusKind kind)
    {
        var (label, brush) = kind switch
        {
            UiStatusKind.Working => ("WORKING", "WorkingBrush"),
            UiStatusKind.Success => ("DONE", "SuccessBrush"),
            UiStatusKind.Review => ("REVIEW", "WarningBrush"),
            UiStatusKind.Error => ("ERROR", "ErrorBrush"),
            _ => ("READY", "AccentBrush")
        };
        StatusBadge.Text = label;
        StatusBadge.SetResourceReference(TextBlock.ForegroundProperty, brush);
        StatusBadgeFrame.SetResourceReference(Border.BorderBrushProperty, brush);
        StatusTitle.SetResourceReference(TextBlock.ForegroundProperty, brush);
        System.Windows.Automation.AutomationProperties.SetItemStatus(StatusPanel, label);
    }
}
