namespace FluidVoice.Hardened;

public static class SecureProfile
{
    public const string ProductName = "FluidVoice Local for Windows";
    public const string ProductVersion = "1.2.0-win11";
    public const string ModelFileName = "ggml-large-v3-turbo-q5_0.bin";
    public const long ModelBytes = 574_041_195;
    public const string ModelSha256 = "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2";
    public const string ModelRevision = "98aa99a0a9db05ae2342309f5096248665f7cba3";
    public const string ModelSource = "https://huggingface.co/ggerganov/whisper.cpp";
    public const int PrimaryHotkeyModifiers = 0x4000; // MOD_NOREPEAT
    public const int PrimaryHotkeyVirtualKey = 0x72; // F3 / Alienware Macro B
    public const int FallbackHotkeyModifiers = 0x0001 | 0x0002 | 0x4000; // Alt + Control + MOD_NOREPEAT
    public const int FallbackHotkeyVirtualKey = 0x20; // Space

    // These are compile-time invariants. There are no setters or alternate code paths.
    public const bool AnalyticsEnabled = false;
    public const bool UpdatesEnabled = false;
    public const bool DebugLoggingEnabled = false;
    public const bool TranscriptionHistoryEnabled = false;
    public const bool AudioHistoryEnabled = false;
    public const bool CommandModeEnabled = false;
    public const bool LocalApiEnabled = false;
    public const bool CloudProvidersEnabled = false;
    public const bool PromptPostProcessingEnabled = false;
}
