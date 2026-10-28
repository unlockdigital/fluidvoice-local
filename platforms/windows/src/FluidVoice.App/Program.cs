using System.Diagnostics;
using FluidVoice.Hardened;

namespace FluidVoice.Hardened.Windows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Trace.Listeners.Clear();
        using var singleInstance = new Mutex(initiallyOwned: true, "Local\\FluidVoiceHardenedWindows", out var createdNew);
        if (!createdNew)
        {
            return;
        }

        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new VoiceApplicationContext());
    }
}
