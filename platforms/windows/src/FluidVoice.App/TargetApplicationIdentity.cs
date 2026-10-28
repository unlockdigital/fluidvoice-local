using System.Diagnostics;

namespace FluidVoice.Hardened.Windows;

internal sealed class TargetApplicationIdentity : IDisposable
{
    internal string DisplayName { get; }
    internal Icon? AppIcon { get; private set; }

    private TargetApplicationIdentity(string displayName, Icon? appIcon)
    {
        DisplayName = displayName;
        AppIcon = appIcon;
    }

    internal static TargetApplicationIdentity Capture(IntPtr windowHandle)
    {
        var displayName = "Current app";
        var appIcon = TryCloneWindowIcon(windowHandle);

        if (windowHandle == IntPtr.Zero ||
            NativeMethods.GetWindowThreadProcessId(windowHandle, out var processId) == 0 ||
            processId == 0)
        {
            return new TargetApplicationIdentity(displayName, appIcon);
        }

        try
        {
            using var process = Process.GetProcessById(checked((int)processId));
            displayName = NormalizeDisplayName(process.ProcessName, displayName);

            string? executablePath = null;
            try
            {
                executablePath = process.MainModule?.FileName;
                if (!string.IsNullOrWhiteSpace(executablePath))
                {
                    var version = FileVersionInfo.GetVersionInfo(executablePath);
                    displayName = NormalizeDisplayName(
                        FirstNonBlank(version.FileDescription, version.ProductName, process.ProcessName),
                        displayName);
                }
            }
            catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
                // Protected or elevated targets may not expose module metadata.
            }

            if (appIcon is null && !string.IsNullOrWhiteSpace(executablePath))
            {
                try
                {
                    appIcon = Icon.ExtractAssociatedIcon(executablePath);
                }
                catch (Exception exception) when (exception is ArgumentException or IOException or System.ComponentModel.Win32Exception)
                {
                    // The neutral local fallback remains available when an executable has no readable icon.
                }
            }
        }
        catch (Exception exception) when (exception is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            // The target may close between capture and lookup. Never change the captured insertion handle.
        }

        return new TargetApplicationIdentity(displayName, appIcon);
    }

    private static Icon? TryCloneWindowIcon(IntPtr windowHandle)
    {
        if (windowHandle == IntPtr.Zero)
        {
            return null;
        }

        foreach (var iconKind in new[] { NativeMethods.IconSmall2, NativeMethods.IconSmall, NativeMethods.IconBig })
        {
            if (NativeMethods.SendMessageTimeout(
                    windowHandle,
                    NativeMethods.WmGetIcon,
                    new IntPtr(iconKind),
                    IntPtr.Zero,
                    NativeMethods.SmtoAbortIfHung,
                    80,
                    out var iconHandle) != IntPtr.Zero &&
                iconHandle != IntPtr.Zero)
            {
                return (Icon)Icon.FromHandle(iconHandle).Clone();
            }
        }

        var classIcon = NativeMethods.GetClassLongPointer(windowHandle, NativeMethods.GclpIconSmall);
        if (classIcon == IntPtr.Zero)
        {
            classIcon = NativeMethods.GetClassLongPointer(windowHandle, NativeMethods.GclpIcon);
        }

        return classIcon == IntPtr.Zero
            ? null
            : (Icon)Icon.FromHandle(classIcon).Clone();
    }

    private static string FirstNonBlank(params string?[] candidates)
    {
        return candidates.FirstOrDefault(candidate => !string.IsNullOrWhiteSpace(candidate)) ?? string.Empty;
    }

    private static string NormalizeDisplayName(string? candidate, string fallback)
    {
        if (string.IsNullOrWhiteSpace(candidate))
        {
            return fallback;
        }

        var normalized = candidate.Trim().Replace("\0", string.Empty, StringComparison.Ordinal);
        if (normalized.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
        {
            normalized = normalized[..^4];
        }

        return normalized.Length > 40 ? normalized[..40] : normalized;
    }

    public void Dispose()
    {
        AppIcon?.Dispose();
        AppIcon = null;
    }
}
