using System.Security.Cryptography;
using System.Text;
using FluidVoice.Hardened;

namespace FluidVoice.Hardened.Windows;

internal sealed class VoiceApplicationContext : ApplicationContext
{
    private static readonly TimeSpan LivePreviewWindow = TimeSpan.FromSeconds(12);
    private static readonly TimeSpan LivePreviewPollInterval = TimeSpan.FromMilliseconds(250);
    private const long MinimumPreviewSampleCount = 16_000;
    private const long MinimumNewPreviewSampleCount = 12_000;

    private readonly NotifyIcon trayIcon;
    private readonly ToolStripMenuItem actionItem;
    private readonly ToolStripMenuItem statusItem;
    private readonly MemoryAudioRecorder recorder = new();
    private readonly RecordingOverlayForm overlay = new();
    private readonly CancellationTokenSource lifetime = new();
    private HotkeyWindow? hotkey;
    private LocalTranscriber? transcriber;
    private CancellationTokenSource? livePreviewCancellation;
    private Task? livePreviewTask;
    private Task activeDictationTask = Task.CompletedTask;
    private IntPtr targetWindow;
    private string livePreviewTranscript = string.Empty;
    private int recordingGeneration;
    private bool busy;
    private bool exiting;

    internal VoiceApplicationContext()
    {
        statusItem = new ToolStripMenuItem("Status: verifying local model") { Enabled = false };
        actionItem = new ToolStripMenuItem("Start Dictation", null, async (_, _) => await RunTrackedToggleAsync())
        {
            Enabled = false
        };
        var privacyItem = new ToolStripMenuItem("Privacy: local-only, no history") { Enabled = false };
        var hotkeyItem = new ToolStripMenuItem("Hotkey: F3 / Macro B (Ctrl+Alt+Space fallback)") { Enabled = false };
        var exitItem = new ToolStripMenuItem("Exit", null, async (_, _) => await ExitSecurelyAsync());

        var menu = new ContextMenuStrip();
        menu.Items.AddRange([statusItem, actionItem, hotkeyItem, privacyItem, new ToolStripSeparator(), exitItem]);

        trayIcon = new NotifyIcon
        {
            Icon = SystemIcons.Shield,
            Text = "FluidVoice Local - verifying local model",
            ContextMenuStrip = menu,
            Visible = true
        };
        trayIcon.DoubleClick += async (_, _) => await RunTrackedToggleAsync();
        recorder.AudioLevelChanged += overlay.SetAudioLevel;
        overlay.StopRequested += async (_, _) => await RunTrackedToggleAsync();

        _ = InitializeAsync();
    }

    private async Task InitializeAsync()
    {
        try
        {
            if (MemoryAudioRecorder.CaptureDeviceCount < 1)
            {
                throw new InvalidOperationException("No microphone capture device is available.");
            }

            var modelPath = Path.Combine(AppContext.BaseDirectory, "Models", SecureProfile.ModelFileName);
            transcriber = await LocalTranscriber.CreateVerifiedAsync(modelPath, lifetime.Token);
            hotkey = new HotkeyWindow();
            hotkey.Pressed += async (_, _) => await RunTrackedToggleAsync();
            actionItem.Enabled = true;
            SetStatus("Ready - F3 / Macro B");
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested)
        {
        }
        catch (Exception)
        {
            actionItem.Enabled = false;
            overlay.ShowError("Startup verification failed");
            SetStatus("HOLD - startup verification failed");
        }
    }

    private async Task ToggleDictationAsync()
    {
        if (busy || transcriber is null || exiting)
        {
            return;
        }

        if (!recorder.IsRecording)
        {
            try
            {
                targetWindow = NativeMethods.GetForegroundWindow();
                recorder.Start();
                actionItem.Text = "Stop and Insert";
                overlay.ShowRecording(targetWindow);
                livePreviewTranscript = string.Empty;
                var generation = Interlocked.Increment(ref recordingGeneration);
                StartLiveTranscriptPreview(transcriber, generation);
                SetStatus("Recording - press F3 / Macro B to stop");
            }
            catch (Exception)
            {
                Interlocked.Increment(ref recordingGeneration);
                recorder.Abort();
                await StopLiveTranscriptPreviewAsync().ConfigureAwait(true);
                livePreviewTranscript = string.Empty;
                actionItem.Text = "Start Dictation";
                actionItem.Enabled = transcriber is not null && !exiting;
                overlay.ShowError("Could not start recording - try again");
                SetStatus("Ready - recording did not start");
            }
            return;
        }

        busy = true;
        actionItem.Enabled = false;
        overlay.ShowProcessing(targetWindow);
        SetStatus("Transcribing locally");
        byte[]? audio = null;
        string? transcript = null;
        var failureMessage = "Could not stop recording - try again";
        try
        {
            audio = await recorder.StopAsync(lifetime.Token);
            Interlocked.Increment(ref recordingGeneration);
            await StopLiveTranscriptPreviewAsync();
            if (audio.Length < 16_000)
            {
                overlay.ShowError("Recording too short");
                SetStatus("Ready - recording was too short");
                return;
            }

            failureMessage = "Could not transcribe - try again";
            await using var wave = new MemoryStream(audio, writable: false);
            transcript = await transcriber.TranscribeAsync(wave, lifetime.Token);
            if (string.IsNullOrWhiteSpace(transcript))
            {
                overlay.ShowError("No speech detected");
                SetStatus("Ready - no speech detected");
                return;
            }

            overlay.SetTranscript(transcript, isFinal: true);
            failureMessage = "Could not insert - return to the original app";
            await UnicodeTextInjector.InsertAsync(targetWindow, transcript, lifetime.Token);
            overlay.ShowSuccess();
            SetStatus("Ready - F3 / Macro B");
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested)
        {
        }
        catch (Exception)
        {
            overlay.ShowError(failureMessage);
            SetStatus($"Ready - {failureMessage}");
        }
        finally
        {
            Interlocked.Increment(ref recordingGeneration);
            await StopLiveTranscriptPreviewAsync();
            if (audio is not null)
            {
                CryptographicOperations.ZeroMemory(audio);
            }
            transcript = null;
            livePreviewTranscript = string.Empty;
            actionItem.Text = "Start Dictation";
            actionItem.Enabled = transcriber is not null && !exiting;
            busy = false;
        }
    }

    private async Task RunTrackedToggleAsync()
    {
        if (!activeDictationTask.IsCompleted)
        {
            return;
        }

        var operation = ToggleDictationAsync();
        activeDictationTask = operation;
        try
        {
            await operation.ConfigureAwait(true);
        }
        finally
        {
            if (ReferenceEquals(activeDictationTask, operation))
            {
                activeDictationTask = Task.CompletedTask;
            }
        }
    }

    private void StartLiveTranscriptPreview(LocalTranscriber activeTranscriber, int generation)
    {
        livePreviewCancellation?.Cancel();
        livePreviewCancellation?.Dispose();
        livePreviewCancellation = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        livePreviewTask = RunLiveTranscriptPreviewAsync(
            activeTranscriber,
            generation,
            livePreviewCancellation.Token);
    }

    private async Task RunLiveTranscriptPreviewAsync(
        LocalTranscriber activeTranscriber,
        int generation,
        CancellationToken cancellationToken)
    {
        var lastPreviewSampleCount = 0L;
        using var timer = new PeriodicTimer(LivePreviewPollInterval);

        try
        {
            while (await timer.WaitForNextTickAsync(cancellationToken).ConfigureAwait(false))
            {
                try
                {
                    if (generation != Volatile.Read(ref recordingGeneration) || !recorder.IsRecording)
                    {
                        return;
                    }

                    using var snapshot = recorder.CopySampleSnapshot(LivePreviewWindow);
                    if (snapshot is null ||
                        snapshot.TotalSampleCount < MinimumPreviewSampleCount ||
                        snapshot.TotalSampleCount - lastPreviewSampleCount < MinimumNewPreviewSampleCount)
                    {
                        continue;
                    }

                    lastPreviewSampleCount = snapshot.TotalSampleCount;
                    var latestWindow = await activeTranscriber.TranscribeSamplesAsync(
                        snapshot.Samples,
                        cancellationToken).ConfigureAwait(false);
                    if (string.IsNullOrWhiteSpace(latestWindow) ||
                        generation != Volatile.Read(ref recordingGeneration) ||
                        cancellationToken.IsCancellationRequested)
                    {
                        continue;
                    }

                    var updatedTranscript = snapshot.FirstSampleIndex == 0
                        ? LiveTranscriptMerger.Normalize(latestWindow)
                        : LiveTranscriptMerger.Merge(livePreviewTranscript, latestWindow);
                    if (updatedTranscript.Length == 0 ||
                        string.Equals(updatedTranscript, livePreviewTranscript, StringComparison.Ordinal))
                    {
                        continue;
                    }

                    livePreviewTranscript = updatedTranscript;
                    overlay.SetTranscript(updatedTranscript);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    return;
                }
                catch (ObjectDisposedException) when (cancellationToken.IsCancellationRequested || exiting)
                {
                    return;
                }
                catch (Exception)
                {
                    await Task.Delay(TimeSpan.FromMilliseconds(500), cancellationToken).ConfigureAwait(false);
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (ObjectDisposedException) when (cancellationToken.IsCancellationRequested || exiting)
        {
        }
        catch (Exception)
        {
            // A provisional preview is optional. The authoritative final local pass still runs on stop.
        }
    }

    private async Task StopLiveTranscriptPreviewAsync()
    {
        var cancellation = livePreviewCancellation;
        var previewTask = livePreviewTask;
        livePreviewCancellation = null;
        livePreviewTask = null;

        cancellation?.Cancel();
        if (previewTask is not null)
        {
            try
            {
                await previewTask.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
        }
        cancellation?.Dispose();
    }

    private void SetStatus(string status)
    {
        statusItem.Text = $"Status: {status}";
        hotkey?.SetOperationalStatus(status);
        trayIcon.Text = status.Length > 60 ? status[..60] : status;
    }

    private async Task ExitSecurelyAsync()
    {
        if (exiting)
        {
            return;
        }
        exiting = true;
        lifetime.Cancel();
        Interlocked.Increment(ref recordingGeneration);
        recorder.Abort();
        await StopLiveTranscriptPreviewAsync().ConfigureAwait(true);
        try
        {
            await activeDictationTask.ConfigureAwait(true);
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested)
        {
        }
        recorder.AudioLevelChanged -= overlay.SetAudioLevel;
        hotkey?.Dispose();
        hotkey = null;
        transcriber?.Dispose();
        transcriber = null;
        trayIcon.Visible = false;
        trayIcon.Dispose();
        overlay.Dispose();
        lifetime.Dispose();
        recorder.Dispose();
        ExitThread();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing && !exiting)
        {
            ExitSecurelyAsync().GetAwaiter().GetResult();
        }
        base.Dispose(disposing);
    }
}

internal static class LiveTranscriptMerger
{
    private const int PreviousWordSearchLimit = 180;
    private const int LatestLeadingWordSearchLimit = 8;
    private const int MaximumUnmatchedPreviousTail = 8;

    internal static string Merge(string previousTranscript, string latestWindow)
    {
        var previous = SplitWords(previousTranscript);
        var latest = SplitWords(latestWindow);
        if (previous.Length == 0)
        {
            return string.Join(' ', latest);
        }
        if (latest.Length == 0)
        {
            return string.Join(' ', previous);
        }

        var previousSearchStart = Math.Max(0, previous.Length - PreviousWordSearchLimit);
        var latestSearchEnd = Math.Min(latest.Length, LatestLeadingWordSearchLimit);
        var bestPreviousStart = -1;
        var bestLatestStart = -1;
        var bestLength = 0;

        for (var previousIndex = previousSearchStart; previousIndex < previous.Length; previousIndex++)
        {
            for (var latestIndex = 0; latestIndex < latestSearchEnd; latestIndex++)
            {
                var length = 0;
                while (previousIndex + length < previous.Length &&
                    latestIndex + length < latest.Length &&
                    WordsEqual(previous[previousIndex + length], latest[latestIndex + length]))
                {
                    length++;
                }

                var unmatchedPreviousTail = previous.Length - (previousIndex + length);
                if (length > bestLength && unmatchedPreviousTail <= MaximumUnmatchedPreviousTail)
                {
                    bestPreviousStart = previousIndex;
                    bestLatestStart = latestIndex;
                    bestLength = length;
                }
            }
        }

        var minimumOverlap = Math.Min(3, Math.Min(previous.Length, latest.Length));
        var hasFuzzyOverlap = TryFindFuzzyOverlap(
            previous,
            latest,
            previousSearchStart,
            out var fuzzyPreviousStart,
            out var fuzzyLatestStart);
        if (hasFuzzyOverlap &&
            (bestLength < minimumOverlap ||
             fuzzyPreviousStart < bestPreviousStart ||
             fuzzyLatestStart < bestLatestStart))
        {
            bestPreviousStart = fuzzyPreviousStart;
            bestLatestStart = fuzzyLatestStart;
        }
        else if (bestLength < minimumOverlap)
        {
            return string.Join(' ', previous.Concat(latest));
        }

        var merged = new string[bestPreviousStart + latest.Length - bestLatestStart];
        Array.Copy(previous, 0, merged, 0, bestPreviousStart);
        Array.Copy(
            latest,
            bestLatestStart,
            merged,
            bestPreviousStart,
            latest.Length - bestLatestStart);
        return string.Join(' ', merged);
    }

    private static bool TryFindFuzzyOverlap(
        string[] previous,
        string[] latest,
        int previousSearchStart,
        out int previousMatchStart,
        out int latestMatchStart)
    {
        var previousLength = previous.Length - previousSearchStart;
        var lengths = new int[previousLength + 1, latest.Length + 1];
        for (var previousIndex = 1; previousIndex <= previousLength; previousIndex++)
        {
            for (var latestIndex = 1; latestIndex <= latest.Length; latestIndex++)
            {
                lengths[previousIndex, latestIndex] = WordsEqual(
                    previous[previousSearchStart + previousIndex - 1],
                    latest[latestIndex - 1])
                    ? lengths[previousIndex - 1, latestIndex - 1] + 1
                    : Math.Max(
                        lengths[previousIndex - 1, latestIndex],
                        lengths[previousIndex, latestIndex - 1]);
            }
        }

        var matches = new List<(int Previous, int Latest)>();
        var previousCursor = previousLength;
        var latestCursor = latest.Length;
        while (previousCursor > 0 && latestCursor > 0)
        {
            if (WordsEqual(
                previous[previousSearchStart + previousCursor - 1],
                latest[latestCursor - 1]))
            {
                matches.Add((
                    previousSearchStart + previousCursor - 1,
                    latestCursor - 1));
                previousCursor--;
                latestCursor--;
            }
            else if (lengths[previousCursor - 1, latestCursor] >= lengths[previousCursor, latestCursor - 1])
            {
                previousCursor--;
            }
            else
            {
                latestCursor--;
            }
        }

        if (matches.Count < 3)
        {
            previousMatchStart = -1;
            latestMatchStart = -1;
            return false;
        }

        matches.Reverse();
        var first = matches[0];
        var comparableSpan = Math.Min(
            previous.Length - first.Previous,
            latest.Length - first.Latest);
        if (comparableSpan < 1 || matches.Count / (float)comparableSpan < 0.34f)
        {
            previousMatchStart = -1;
            latestMatchStart = -1;
            return false;
        }

        previousMatchStart = first.Previous;
        latestMatchStart = first.Latest;
        return true;
    }

    internal static string Normalize(string value)
    {
        return string.Join(' ', SplitWords(value));
    }

    private static string[] SplitWords(string value)
    {
        return string.IsNullOrWhiteSpace(value)
            ? []
            : value.Split(
                (char[]?)null,
                StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    }

    private static bool WordsEqual(string left, string right)
    {
        return string.Equals(
            ComparableWord(left),
            ComparableWord(right),
            StringComparison.Ordinal);
    }

    private static string ComparableWord(string value)
    {
        var comparable = new StringBuilder(value.Length);
        foreach (var character in value)
        {
            if (char.IsLetterOrDigit(character))
            {
                comparable.Append(char.ToLowerInvariant(character));
            }
        }

        return comparable.Length == 0 ? value.ToLowerInvariant() : comparable.ToString();
    }
}
