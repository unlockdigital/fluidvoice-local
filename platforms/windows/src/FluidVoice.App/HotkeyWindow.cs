using FluidVoice.Hardened;

namespace FluidVoice.Hardened.Windows;

internal sealed class HotkeyWindow : NativeWindow, IDisposable
{
    private const int PrimaryHotkeyId = 0x4656;
    private const int FallbackHotkeyId = 0x4657;
    private bool primaryRegistered;
    private bool fallbackRegistered;
    private bool disposed;

    internal event EventHandler? Pressed;

    internal HotkeyWindow()
    {
        CreateHandle(new CreateParams { Caption = "FluidVoiceHardenedHotkeyWindow:Initializing" });
        primaryRegistered = NativeMethods.RegisterHotKey(
            Handle,
            PrimaryHotkeyId,
            SecureProfile.PrimaryHotkeyModifiers,
            SecureProfile.PrimaryHotkeyVirtualKey);

        if (!primaryRegistered)
        {
            var error = System.Runtime.InteropServices.Marshal.GetLastWin32Error();
            DestroyHandle();
            throw new System.ComponentModel.Win32Exception(error, "F3 (Alienware Macro B) is already registered by another application.");
        }

        fallbackRegistered = NativeMethods.RegisterHotKey(
            Handle,
            FallbackHotkeyId,
            SecureProfile.FallbackHotkeyModifiers,
            SecureProfile.FallbackHotkeyVirtualKey);

        if (!fallbackRegistered)
        {
            var error = System.Runtime.InteropServices.Marshal.GetLastWin32Error();
            NativeMethods.UnregisterHotKey(Handle, PrimaryHotkeyId);
            primaryRegistered = false;
            DestroyHandle();
            throw new System.ComponentModel.Win32Exception(error, "Ctrl+Alt+Space is already registered by another application.");
        }
    }

    internal void SetOperationalStatus(string status)
    {
        NativeMethods.SetWindowText(Handle, $"FluidVoiceHardenedHotkeyWindow:{status}");
    }

    protected override void WndProc(ref Message message)
    {
        var hotkeyId = message.WParam.ToInt32();
        if (message.Msg == NativeMethods.WmHotkey &&
            hotkeyId is PrimaryHotkeyId or FallbackHotkeyId)
        {
            Pressed?.Invoke(this, EventArgs.Empty);
        }
        base.WndProc(ref message);
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        if (fallbackRegistered)
        {
            NativeMethods.UnregisterHotKey(Handle, FallbackHotkeyId);
            fallbackRegistered = false;
        }
        if (primaryRegistered)
        {
            NativeMethods.UnregisterHotKey(Handle, PrimaryHotkeyId);
            primaryRegistered = false;
        }
        DestroyHandle();
        disposed = true;
        GC.SuppressFinalize(this);
    }
}
