using System.ComponentModel;
using System.Runtime.InteropServices;

namespace FluidVoice.Hardened.Windows;

internal static class UnicodeTextInjector
{
    internal static async Task InsertAsync(IntPtr targetWindow, string text, CancellationToken cancellationToken = default)
    {
        if (targetWindow == IntPtr.Zero || !NativeMethods.IsWindow(targetWindow))
        {
            throw new InvalidOperationException("The original dictation target is no longer available.");
        }

        if (NativeMethods.GetForegroundWindow() != targetWindow)
        {
            if (!NativeMethods.SetForegroundWindow(targetWindow))
            {
                throw new InvalidOperationException("Windows did not allow FluidVoice Local to restore the original dictation target.");
            }
            await Task.Delay(125, cancellationToken).ConfigureAwait(true);
        }

        if (!NativeMethods.IsWindow(targetWindow) || NativeMethods.GetForegroundWindow() != targetWindow)
        {
            throw new InvalidOperationException("The original dictation target could not be focused safely.");
        }

        const int batchCharacters = 128;
        for (var offset = 0; offset < text.Length; offset += batchCharacters)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!NativeMethods.IsWindow(targetWindow) || NativeMethods.GetForegroundWindow() != targetWindow)
            {
                throw new InvalidOperationException("The dictation target lost focus before insertion completed.");
            }

            var count = Math.Min(batchCharacters, text.Length - offset);
            var inputs = new NativeMethods.Input[count * 2];

            for (var index = 0; index < count; index++)
            {
                var character = text[offset + index];
                inputs[index * 2] = CreateInput(character, keyUp: false);
                inputs[(index * 2) + 1] = CreateInput(character, keyUp: true);
            }

            var sent = NativeMethods.SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<NativeMethods.Input>());
            if (sent != inputs.Length)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(),
                    "Windows blocked text insertion. Elevated applications require a matching integrity level.");
            }
        }
    }

    private static NativeMethods.Input CreateInput(char character, bool keyUp)
    {
        return new NativeMethods.Input
        {
            Type = NativeMethods.InputKeyboard,
            Union = new NativeMethods.InputUnion
            {
                Keyboard = new NativeMethods.KeyboardInput
                {
                    ScanCode = character,
                    Flags = NativeMethods.KeyEventUnicode | (keyUp ? NativeMethods.KeyEventKeyUp : 0)
                }
            }
        };
    }
}
