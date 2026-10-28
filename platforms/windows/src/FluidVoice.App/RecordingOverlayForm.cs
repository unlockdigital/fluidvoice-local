using System.Diagnostics;
using System.Drawing.Drawing2D;

namespace FluidVoice.Hardened.Windows;

internal enum RecordingOverlayState
{
    Recording,
    Processing,
    Success,
    Error
}

internal sealed class RecordingOverlayForm : Form
{
    private const int CompactWidth = 310;
    private const int ExpandedWidth = 540;
    private const int ControlRailHeight = 64;
    private const int TranscriptHorizontalInset = 18;
    private const int TranscriptTextInset = 14;
    private const int TranscriptTopPadding = 11;
    private const int TranscriptBottomPadding = 11;
    private const int MaximumVisibleTranscriptLines = 5;
    private const int WaveformBars = 18;
    private const int ScreenBottomInset = 26;
    private const int SuccessConfirmationMilliseconds = 350;
    private const int WsExToolWindow = 0x00000080;
    private const int WsExNoActivate = 0x08000000;

    private readonly float[] waveform = new float[WaveformBars];
    private readonly System.Windows.Forms.Timer animationTimer;
    private readonly System.Windows.Forms.Timer dismissTimer;
    private readonly System.Windows.Forms.Timer transcriptLayoutTimer;
    private readonly Stopwatch recordingElapsed = new();
    private readonly Font timerFont = new("Segoe UI Variable Text", 9.25f, FontStyle.Regular, GraphicsUnit.Point);
    private readonly Font statusFont = new("Segoe UI Variable Text", 8.5f, FontStyle.Regular, GraphicsUnit.Point);
    private readonly Font transcriptFont = new("Segoe UI Variable Text", 13f, FontStyle.Regular, GraphicsUnit.Point);
    private List<string> cachedWrappedLines = [string.Empty];
    private TargetApplicationIdentity targetApplication = TargetApplicationIdentity.Capture(IntPtr.Zero);
    private IntPtr displayedTargetWindow;
    private Rectangle overlayWorkingArea;
    private Size targetClientSize = new(CompactWidth, ControlRailHeight);
    private string transcript = string.Empty;
    private string statusMessage = string.Empty;
    private string cachedWrappedText = string.Empty;
    private float targetLevel;
    private float smoothedLevel;
    private float targetChangeHighlight;
    private int animationFrame;
    private int transcriptScrollOffset;
    private int lastWrappedLineCount;
    private int lastVisibleLineCapacity;
    private int cachedWrapWidth = -1;
    private int cachedWrapDpi = -1;
    private int preservedWrappedLineCount;
    private int wheelDeltaRemainder;
    private float layoutScale = 1f;
    private RecordingOverlayState visualState = RecordingOverlayState.Recording;
    private bool transcriptIsFinal;
    private bool preserveScrollAnchorOnNextWrap;
    private bool stopControlHovered;
    private bool stopControlPressed;
    private bool scrollbarHovered;
    private bool disposed;

    internal event EventHandler? StopRequested;

    internal RecordingOverlayForm()
    {
        AutoScaleMode = AutoScaleMode.None;
        BackColor = Color.FromArgb(20, 20, 25);
        ClientSize = new Size(CompactWidth, ControlRailHeight);
        ControlBox = false;
        DoubleBuffered = true;
        FormBorderStyle = FormBorderStyle.None;
        MaximizeBox = false;
        MinimizeBox = false;
        Name = "FluidVoiceRecordingOverlay";
        ShowIcon = false;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        Text = "FluidVoice Local";
        TopMost = true;
        AccessibleName = "FluidVoice Local live dictation";
        AccessibleRole = AccessibleRole.Pane;
        AccessibleDefaultActionDescription = string.Empty;

        animationTimer = new System.Windows.Forms.Timer { Interval = 33 };
        animationTimer.Tick += (_, _) => AdvanceAnimation();
        dismissTimer = new System.Windows.Forms.Timer();
        dismissTimer.Tick += (_, _) =>
        {
            dismissTimer.Stop();
            HideOverlay();
        };
        transcriptLayoutTimer = new System.Windows.Forms.Timer { Interval = 90 };
        transcriptLayoutTimer.Tick += (_, _) =>
        {
            transcriptLayoutTimer.Stop();
            UpdateTranscriptLayout();
        };

        MouseClick += (_, args) =>
        {
            if (args.Button == MouseButtons.Left &&
                visualState == RecordingOverlayState.Recording &&
                GetStateControlHitBounds().Contains(args.Location))
            {
                RequestStop();
            }
            else if (args.Button == MouseButtons.Left &&
                GetScrollbarHitBounds().Contains(args.Location))
            {
                ScrollTranscriptTo(args.Location.Y);
            }
        };
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var parameters = base.CreateParams;
            parameters.ExStyle |= WsExToolWindow | WsExNoActivate;
            return parameters;
        }
    }

    protected override AccessibleObject CreateAccessibilityInstance()
    {
        return new RecordingOverlayAccessibleObject(this);
    }

    internal void ShowRecording(IntPtr targetWindow)
    {
        visualState = RecordingOverlayState.Recording;
        targetChangeHighlight = 0;
        transcript = string.Empty;
        statusMessage = string.Empty;
        transcriptIsFinal = false;
        transcriptScrollOffset = 0;
        lastWrappedLineCount = 0;
        lastVisibleLineCapacity = 0;
        wheelDeltaRemainder = 0;
        preserveScrollAnchorOnNextWrap = false;
        stopControlHovered = false;
        stopControlPressed = false;
        scrollbarHovered = false;
        InvalidateTranscriptWrap();
        UpdateTargetApplication(targetWindow, highlightChange: false);
        UpdateWorkingArea(targetWindow);
        AccessibleDefaultActionDescription = "Stop recording and insert the final transcript";
        SetAccessibleDescription(
            $"FluidVoice Local is listening for {targetApplication.DisplayName}. " +
            "Live transcript will appear here. Press F3 or click the stop control to finish and insert.",
            announceStateChange: true);
        targetLevel = 0;
        smoothedLevel = 0;
        animationFrame = 0;
        Array.Clear(waveform);
        recordingElapsed.Restart();
        dismissTimer.Stop();
        transcriptLayoutTimer.Stop();
        targetClientSize = DpiSize(CompactWidth, ControlRailHeight);
        ClientSize = targetClientSize;
        PositionForSize(targetClientSize);
        Cursor = Cursors.Default;
        ShowOverlay();
        ScheduleTranscriptLayout();
    }

    internal void ShowProcessing(IntPtr targetWindow)
    {
        visualState = RecordingOverlayState.Processing;
        UpdateTargetApplication(targetWindow, highlightChange: false);
        UpdateWorkingArea(targetWindow);
        targetChangeHighlight = 0;
        statusMessage = "Transcribing locally";
        AccessibleDefaultActionDescription = string.Empty;
        SetAccessibleDescription(
            string.IsNullOrEmpty(transcript)
                ? $"FluidVoice Local is transcribing locally for {targetApplication.DisplayName}."
                : $"FluidVoice Local is finalizing this local transcript for {targetApplication.DisplayName}: {transcript}",
            announceStateChange: true);
        recordingElapsed.Stop();
        Cursor = Cursors.Default;
        dismissTimer.Stop();
        ShowOverlay();
        ScheduleTranscriptLayout();
    }

    internal void ShowSuccess()
    {
        visualState = RecordingOverlayState.Success;
        statusMessage = "Inserted";
        transcriptIsFinal = true;
        AccessibleDefaultActionDescription = string.Empty;
        SetAccessibleDescription(
            string.IsNullOrEmpty(transcript)
                ? $"FluidVoice Local inserted the dictation into {targetApplication.DisplayName}."
                : $"FluidVoice Local inserted this dictation into {targetApplication.DisplayName}: {transcript}",
            announceStateChange: true);
        recordingElapsed.Stop();
        Cursor = Cursors.Default;
        transcriptLayoutTimer.Stop();
        UpdateTranscriptLayout();
        ClientSize = targetClientSize;
        PositionForSize(targetClientSize);
        ShowOverlay();
        ScheduleDismiss(SuccessConfirmationMilliseconds);
    }

    internal void ShowError(string message)
    {
        visualState = RecordingOverlayState.Error;
        statusMessage = message;
        transcriptIsFinal = true;
        AccessibleDefaultActionDescription = string.Empty;
        SetAccessibleDescription(
            string.IsNullOrEmpty(transcript)
                ? message
                : $"{message}. Last local transcript preview: {transcript}",
            announceStateChange: true);
        recordingElapsed.Stop();
        Cursor = Cursors.Default;
        ShowOverlay();
        ScheduleTranscriptLayout();
        ScheduleDismiss(2200);
    }

    internal void SetTranscript(string value, bool isFinal = false)
    {
        if (disposed)
        {
            return;
        }

        if (InvokeRequired)
        {
            try
            {
                BeginInvoke((Action)(() => SetTranscript(value, isFinal)));
            }
            catch (InvalidOperationException)
            {
            }
            return;
        }

        var normalized = NormalizeTranscript(value);
        if (string.Equals(transcript, normalized, StringComparison.Ordinal) && transcriptIsFinal == isFinal)
        {
            return;
        }

        if (transcriptScrollOffset > 0)
        {
            preserveScrollAnchorOnNextWrap = true;
            preservedWrappedLineCount = lastWrappedLineCount;
        }
        transcript = normalized;
        transcriptIsFinal = isFinal;
        InvalidateTranscriptWrap();

        var updatedAccessibleDescription = visualState switch
        {
            RecordingOverlayState.Recording when !string.IsNullOrEmpty(transcript) =>
                $"FluidVoice Local live local transcript for {targetApplication.DisplayName}: {transcript}",
            RecordingOverlayState.Processing when !string.IsNullOrEmpty(transcript) =>
                $"FluidVoice Local is finalizing this local transcript for {targetApplication.DisplayName}: {transcript}",
            _ => AccessibleDescription
        };
        SetAccessibleDescription(updatedAccessibleDescription);

        ScheduleTranscriptLayout();
        Invalidate();
    }

    internal void SetAudioLevel(float level)
    {
        if (disposed || visualState != RecordingOverlayState.Recording)
        {
            return;
        }

        if (InvokeRequired)
        {
            try
            {
                BeginInvoke((Action)(() => SetAudioLevel(level)));
            }
            catch (InvalidOperationException)
            {
            }
            return;
        }

        targetLevel = Math.Max(targetLevel, Math.Clamp(level * 5.5f, 0f, 1f));
    }

    private void ShowOverlay()
    {
        if (overlayWorkingArea.Width <= 0 || overlayWorkingArea.Height <= 0)
        {
            UpdateWorkingArea(displayedTargetWindow);
            PositionForSize(ClientSize);
        }

        if (!Visible)
        {
            Show();
        }
        animationTimer.Start();
        Invalidate();
    }

    private void HideOverlay()
    {
        animationTimer.Stop();
        dismissTimer.Stop();
        transcriptLayoutTimer.Stop();
        recordingElapsed.Stop();
        transcript = string.Empty;
        statusMessage = string.Empty;
        transcriptIsFinal = false;
        transcriptScrollOffset = 0;
        lastWrappedLineCount = 0;
        lastVisibleLineCapacity = 0;
        wheelDeltaRemainder = 0;
        preserveScrollAnchorOnNextWrap = false;
        preservedWrappedLineCount = 0;
        stopControlHovered = false;
        stopControlPressed = false;
        scrollbarHovered = false;
        InvalidateTranscriptWrap();
        AccessibleDefaultActionDescription = string.Empty;
        SetAccessibleDescription(string.Empty, announceStateChange: true);
        Cursor = Cursors.Default;
        targetClientSize = DpiSize(CompactWidth, ControlRailHeight);
        if (Visible)
        {
            Hide();
        }
    }

    private void ScheduleDismiss(int milliseconds)
    {
        dismissTimer.Stop();
        dismissTimer.Interval = milliseconds;
        dismissTimer.Start();
    }

    private void ScheduleTranscriptLayout()
    {
        if (disposed)
        {
            return;
        }

        transcriptLayoutTimer.Stop();
        transcriptLayoutTimer.Start();
    }

    private void UpdateTranscriptLayout()
    {
        if (disposed)
        {
            return;
        }

        var desiredWidth = Math.Clamp(
            Math.Min(Dpi(ExpandedWidth), overlayWorkingArea.Width - Dpi(48)),
            Dpi(CompactWidth),
            Dpi(ExpandedWidth));
        var availableTextWidth = Math.Max(
            Dpi(120),
            desiredWidth - (Dpi(TranscriptHorizontalInset) * 2) - Dpi(TranscriptTextInset));
        var displayText = GetTranscriptDisplayText();
        using var graphics = CreateGraphics();
        var lineHeight = Math.Max(
            Dpi(20),
            (int)Math.Ceiling(transcriptFont.GetHeight(graphics) + Dpi(2f)));
        var measuredLines = Math.Max(
            1,
            GetWrappedTranscriptLines(graphics, displayText, availableTextWidth).Count);
        var visibleLines = Math.Min(MaximumVisibleTranscriptLines, measuredLines);
        var desiredHeight = Dpi(ControlRailHeight) +
            Dpi(TranscriptTopPadding) +
            (visibleLines * lineHeight) +
            Dpi(TranscriptBottomPadding) +
            Dpi(3);
        desiredHeight = Math.Min(
            desiredHeight,
            Math.Max(Dpi(ControlRailHeight), overlayWorkingArea.Height - Dpi(52)));
        targetClientSize = new Size(desiredWidth, desiredHeight);
    }

    private void UpdateWorkingArea(IntPtr targetWindow)
    {
        var screen = targetWindow == IntPtr.Zero
            ? Screen.PrimaryScreen
            : Screen.FromHandle(targetWindow);
        overlayWorkingArea = (screen ?? Screen.PrimaryScreen)?.WorkingArea ??
            new Rectangle(0, 0, 1920, 1080);
        var windowDpi = targetWindow == IntPtr.Zero
            ? (uint)Math.Max(96, DeviceDpi)
            : NativeMethods.GetDpiForWindow(targetWindow);
        if (windowDpi >= 96)
        {
            layoutScale = Math.Clamp(windowDpi / 96f, 1f, 5f);
        }
    }

    private void PositionForSize(Size size)
    {
        if (overlayWorkingArea.Width <= 0 || overlayWorkingArea.Height <= 0)
        {
            UpdateWorkingArea(displayedTargetWindow);
        }

        Location = new Point(
            overlayWorkingArea.Left + ((overlayWorkingArea.Width - size.Width) / 2),
            overlayWorkingArea.Bottom - size.Height - Dpi(ScreenBottomInset));
    }

    private void AdvanceAnimation()
    {
        animationFrame++;
        targetChangeHighlight = Math.Max(0f, targetChangeHighlight - 0.075f);

        if (visualState is RecordingOverlayState.Recording or RecordingOverlayState.Processing &&
            animationFrame % 15 == 0)
        {
            var previousWorkingArea = overlayWorkingArea;
            var previousScale = layoutScale;
            UpdateWorkingArea(displayedTargetWindow);
            if (overlayWorkingArea != previousWorkingArea ||
                Math.Abs(layoutScale - previousScale) > 0.001f)
            {
                PositionForSize(ClientSize);
                ScheduleTranscriptLayout();
            }
        }

        for (var index = 0; index < waveform.Length - 1; index++)
        {
            waveform[index] = waveform[index + 1];
        }

        if (visualState == RecordingOverlayState.Recording)
        {
            smoothedLevel += (targetLevel - smoothedLevel) * 0.48f;
            targetLevel *= 0.72f;
            var pulse = 0.025f + (0.018f * MathF.Sin(animationFrame * 0.31f));
            waveform[^1] = Math.Clamp(smoothedLevel + pulse, 0.03f, 1f);
        }
        else if (visualState == RecordingOverlayState.Processing)
        {
            var phase = animationFrame * 0.22f;
            waveform[^1] = 0.2f + (0.55f * MathF.Abs(MathF.Sin(phase)));
        }
        else
        {
            waveform[^1] = Math.Max(0.04f, waveform[^2] * 0.8f);
        }

        AnimateClientSize();
        Invalidate();
    }

    private void AnimateClientSize()
    {
        var current = ClientSize;
        var nextWidth = Approach(current.Width, targetClientSize.Width);
        var nextHeight = Approach(current.Height, targetClientSize.Height);
        if (nextWidth == current.Width && nextHeight == current.Height)
        {
            return;
        }

        var nextSize = new Size(nextWidth, nextHeight);
        SetBounds(
            overlayWorkingArea.Left + ((overlayWorkingArea.Width - nextSize.Width) / 2),
            overlayWorkingArea.Bottom - nextSize.Height - Dpi(ScreenBottomInset),
            nextSize.Width,
            nextSize.Height);
    }

    private static int Approach(int current, int target)
    {
        var difference = target - current;
        if (Math.Abs(difference) <= 1)
        {
            return target;
        }

        var step = Math.Max(1, (int)Math.Ceiling(Math.Abs(difference) * 0.24));
        return current + (Math.Sign(difference) * step);
    }

    protected override void OnMouseWheel(MouseEventArgs eventArgs)
    {
        base.OnMouseWheel(eventArgs);
        if (lastWrappedLineCount <= lastVisibleLineCapacity || lastVisibleLineCapacity < 1)
        {
            wheelDeltaRemainder = 0;
            return;
        }

        wheelDeltaRemainder += eventArgs.Delta;
        var detents = wheelDeltaRemainder / SystemInformation.MouseWheelScrollDelta;
        if (detents == 0)
        {
            return;
        }
        wheelDeltaRemainder -= detents * SystemInformation.MouseWheelScrollDelta;

        var configuredLines = SystemInformation.MouseWheelScrollLines;
        if (configuredLines == 0)
        {
            return;
        }
        var linesPerDetent = configuredLines < 0
            ? lastVisibleLineCapacity
            : Math.Max(1, configuredLines);
        var maximumOffset = Math.Max(0, lastWrappedLineCount - lastVisibleLineCapacity);
        transcriptScrollOffset = Math.Clamp(
            transcriptScrollOffset + (detents * linesPerDetent),
            0,
            maximumOffset);
        Invalidate();
    }

    protected override void OnMouseMove(MouseEventArgs eventArgs)
    {
        base.OnMouseMove(eventArgs);
        var nextStopHover = visualState == RecordingOverlayState.Recording &&
            GetStateControlHitBounds().Contains(eventArgs.Location);
        var nextScrollbarHover = GetScrollbarHitBounds().Contains(eventArgs.Location);
        if (stopControlHovered != nextStopHover || scrollbarHovered != nextScrollbarHover)
        {
            stopControlHovered = nextStopHover;
            scrollbarHovered = nextScrollbarHover;
            Invalidate();
        }

        Cursor = stopControlHovered || scrollbarHovered
            ? Cursors.Hand
            : Cursors.Default;
    }

    protected override void OnMouseDown(MouseEventArgs eventArgs)
    {
        base.OnMouseDown(eventArgs);
        if (eventArgs.Button == MouseButtons.Left &&
            visualState == RecordingOverlayState.Recording &&
            GetStateControlHitBounds().Contains(eventArgs.Location))
        {
            stopControlPressed = true;
            Invalidate();
        }
    }

    protected override void OnMouseUp(MouseEventArgs eventArgs)
    {
        base.OnMouseUp(eventArgs);
        if (stopControlPressed)
        {
            stopControlPressed = false;
            Invalidate();
        }
    }

    protected override void OnMouseLeave(EventArgs eventArgs)
    {
        base.OnMouseLeave(eventArgs);
        if (stopControlHovered || stopControlPressed || scrollbarHovered)
        {
            stopControlHovered = false;
            stopControlPressed = false;
            scrollbarHovered = false;
            Cursor = Cursors.Default;
            Invalidate();
        }
    }

    protected override void OnResize(EventArgs eventArgs)
    {
        base.OnResize(eventArgs);
        if (Width < 1 || Height < 1)
        {
            return;
        }

        using var path = CreateRoundedPath(new RectangleF(0, 0, Width, Height), Dpi(18f));
        var previousRegion = Region;
        Region = new Region(path);
        previousRegion?.Dispose();
    }

    protected override void OnDpiChanged(DpiChangedEventArgs eventArgs)
    {
        base.OnDpiChanged(eventArgs);
        layoutScale = Math.Clamp(eventArgs.DeviceDpiNew / 96f, 1f, 5f);
        InvalidateTranscriptWrap();
        UpdateWorkingArea(displayedTargetWindow);
        UpdateTranscriptLayout();
        PositionForSize(ClientSize);
        Invalidate();
    }

    protected override void OnPaintBackground(PaintEventArgs eventArgs)
    {
    }

    protected override void OnPaint(PaintEventArgs eventArgs)
    {
        base.OnPaint(eventArgs);
        var graphics = eventArgs.Graphics;
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
        graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

        var bounds = new RectangleF(0, 0, Width, Height);
        using var backgroundPath = CreateRoundedPath(bounds, Dpi(18f));
        using var background = new LinearGradientBrush(
            bounds,
            Color.FromArgb(255, 32, 31, 40),
            Color.FromArgb(255, 17, 18, 23),
            LinearGradientMode.Vertical);
        graphics.FillPath(background, backgroundPath);

        using (var border = new Pen(Color.FromArgb(46, 255, 255, 255), Dpi(1f)))
        {
            graphics.DrawPath(border, backgroundPath);
        }

        var railTop = Height - Dpi(ControlRailHeight);
        if (railTop > Dpi(2))
        {
            DrawTranscript(graphics, railTop);
            using var separator = new Pen(Color.FromArgb(28, 255, 255, 255), Dpi(1f));
            graphics.DrawLine(separator, Dpi(16), railTop, Width - Dpi(16), railTop);
        }

        DrawTargetApplication(graphics, railTop);
        DrawWaveform(graphics, railTop);
        DrawStatus(graphics, railTop);
        DrawTimer(graphics, railTop);
        DrawStateControl(graphics, railTop);
    }

    private void DrawTranscript(Graphics graphics, int railTop)
    {
        var area = new RectangleF(
            Dpi(TranscriptHorizontalInset + TranscriptTextInset),
            Dpi(TranscriptTopPadding),
            Width - Dpi((TranscriptHorizontalInset * 2) + TranscriptTextInset),
            railTop - Dpi(TranscriptTopPadding) - Dpi(TranscriptBottomPadding));
        if (area.Width < Dpi(20) || area.Height < Dpi(10))
        {
            return;
        }

        var displayText = GetTranscriptDisplayText();
        var lines = GetWrappedTranscriptLines(graphics, displayText, area.Width);
        var lineHeight = Math.Max(
            Dpi(20f),
            transcriptFont.GetHeight(graphics) + Dpi(2f));
        var visibleCapacity = Math.Max(1, Math.Min(
            MaximumVisibleTranscriptLines,
            (int)Math.Floor((area.Height + Dpi(2f)) / lineHeight)));
        lastWrappedLineCount = lines.Count;
        lastVisibleLineCapacity = visibleCapacity;

        var maximumOffset = Math.Max(0, lines.Count - visibleCapacity);
        transcriptScrollOffset = Math.Clamp(transcriptScrollOffset, 0, maximumOffset);
        var lastExclusive = Math.Max(0, lines.Count - transcriptScrollOffset);
        var firstVisible = Math.Max(0, lastExclusive - visibleCapacity);
        var stateColor = GetAccentColor();
        var dotPulse = visualState == RecordingOverlayState.Recording
            ? 0.72f + (0.28f * (0.5f + (0.5f * MathF.Sin(animationFrame * 0.18f))))
            : 1f;

        using (var dotBrush = new SolidBrush(Color.FromArgb(
            Math.Clamp((int)(235 * dotPulse), 0, 255),
            stateColor)))
        {
            graphics.FillEllipse(
                dotBrush,
                Dpi(TranscriptHorizontalInset),
                area.Top + ((lineHeight - Dpi(7f)) / 2f),
                Dpi(7f),
                Dpi(7f));
        }

        var placeholder = string.IsNullOrEmpty(transcript);
        for (var index = firstVisible; index < lastExclusive; index++)
        {
            var isRevisableTail = !placeholder &&
                visualState == RecordingOverlayState.Recording &&
                !transcriptIsFinal &&
                index == lines.Count - 1;
            var color = placeholder
                ? Color.FromArgb(150, 211, 213, 224)
                : isRevisableTail
                    ? Color.FromArgb(224, 184, 178, 255)
                    : Color.FromArgb(235, 241, 242, 248);
            using var textBrush = new SolidBrush(color);
            var y = area.Top + ((index - firstVisible) * lineHeight);
            graphics.DrawString(
                lines[index],
                transcriptFont,
                textBrush,
                new PointF(area.Left, y),
                StringFormat.GenericTypographic);
        }

        if (lines.Count > visibleCapacity)
        {
            var trackHeight = Math.Max(Dpi(18f), area.Height - Dpi(4f));
            var thumbHeight = Math.Max(Dpi(15f), trackHeight * visibleCapacity / lines.Count);
            var scrollRange = Math.Max(Dpi(1f), trackHeight - thumbHeight);
            var bottomProgress = maximumOffset == 0
                ? 1f
                : 1f - (transcriptScrollOffset / (float)maximumOffset);
            var thumbTop = area.Top + Dpi(2f) + (scrollRange * bottomProgress);
            var scrollbarWidth = scrollbarHovered ? Dpi(4f) : Dpi(2f);
            var scrollbarX = Width - Dpi(9f) - (scrollbarWidth / 2f);
            using var track = new SolidBrush(Color.FromArgb(
                scrollbarHovered ? 42 : 24,
                255,
                255,
                255));
            using var thumb = new SolidBrush(Color.FromArgb(
                scrollbarHovered ? 156 : 92,
                184,
                178,
                255));
            graphics.FillRectangle(track, scrollbarX, area.Top + Dpi(2f), scrollbarWidth, trackHeight);
            graphics.FillRectangle(thumb, scrollbarX, thumbTop, scrollbarWidth, thumbHeight);
        }
    }

    private List<string> GetWrappedTranscriptLines(
        Graphics graphics,
        string value,
        float maximumWidth)
    {
        var widthKey = Math.Max(1, (int)Math.Round(maximumWidth));
        var dpiKey = (int)Math.Round(layoutScale * 1000f);
        if (cachedWrapWidth == widthKey &&
            cachedWrapDpi == dpiKey &&
            string.Equals(cachedWrappedText, value, StringComparison.Ordinal))
        {
            return cachedWrappedLines;
        }

        var wrappedLines = WrapTranscript(graphics, value, maximumWidth);
        if (preserveScrollAnchorOnNextWrap && preservedWrappedLineCount > 0)
        {
            transcriptScrollOffset = Math.Max(
                0,
                transcriptScrollOffset + wrappedLines.Count - preservedWrappedLineCount);
            preserveScrollAnchorOnNextWrap = false;
            preservedWrappedLineCount = 0;
        }

        cachedWrappedText = value;
        cachedWrapWidth = widthKey;
        cachedWrapDpi = dpiKey;
        cachedWrappedLines = wrappedLines;
        return cachedWrappedLines;
    }

    private void InvalidateTranscriptWrap()
    {
        cachedWrappedText = string.Empty;
        cachedWrapWidth = -1;
        cachedWrapDpi = -1;
        cachedWrappedLines = [string.Empty];
    }

    private List<string> WrapTranscript(Graphics graphics, string value, float maximumWidth)
    {
        var words = value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        var lines = new List<string>();
        var currentLine = string.Empty;

        foreach (var word in words)
        {
            var candidate = currentLine.Length == 0 ? word : $"{currentLine} {word}";
            if (MeasureTextWidth(graphics, candidate) <= maximumWidth)
            {
                currentLine = candidate;
                continue;
            }

            if (currentLine.Length > 0)
            {
                lines.Add(currentLine);
                currentLine = string.Empty;
            }

            if (MeasureTextWidth(graphics, word) <= maximumWidth)
            {
                currentLine = word;
                continue;
            }

            var remaining = word;
            while (remaining.Length > 0)
            {
                var fittingLength = FindFittingPrefixLength(graphics, remaining, maximumWidth);
                var piece = remaining[..fittingLength];
                remaining = remaining[fittingLength..];
                if (remaining.Length == 0)
                {
                    currentLine = piece;
                }
                else
                {
                    lines.Add(piece);
                }
            }
        }

        if (currentLine.Length > 0)
        {
            lines.Add(currentLine);
        }

        if (lines.Count == 0)
        {
            lines.Add(string.Empty);
        }

        return lines;
    }

    private int FindFittingPrefixLength(Graphics graphics, string value, float maximumWidth)
    {
        var low = 1;
        var high = value.Length;
        var best = 1;
        while (low <= high)
        {
            var midpoint = low + ((high - low) / 2);
            if (MeasureTextWidth(graphics, value[..midpoint]) <= maximumWidth)
            {
                best = midpoint;
                low = midpoint + 1;
            }
            else
            {
                high = midpoint - 1;
            }
        }

        return best;
    }

    private float MeasureTextWidth(Graphics graphics, string value)
    {
        return graphics.MeasureString(
            value,
            transcriptFont,
            int.MaxValue,
            StringFormat.GenericTypographic).Width;
    }

    private void DrawTargetApplication(Graphics graphics, int railTop)
    {
        var logoBounds = new RectangleF(Dpi(10f), railTop + Dpi(12f), Dpi(40f), Dpi(40f));
        using var logoPath = CreateRoundedPath(logoBounds, Dpi(12f));
        using var logoBrush = new SolidBrush(Color.FromArgb(235, 238, 244));
        graphics.FillPath(logoBrush, logoPath);

        if (targetApplication.AppIcon is not null)
        {
            graphics.DrawIcon(
                targetApplication.AppIcon,
                new Rectangle(Dpi(16), railTop + Dpi(18), Dpi(28), Dpi(28)));
        }
        else
        {
            DrawFallbackMark(graphics, logoBounds);
        }

        if (targetChangeHighlight > 0f)
        {
            var highlightAlpha = Math.Clamp((int)(220f * targetChangeHighlight), 0, 220);
            using var highlight = new Pen(Color.FromArgb(highlightAlpha, 117, 132, 255), Dpi(2f));
            graphics.DrawPath(highlight, logoPath);
        }

        using var separator = new Pen(Color.FromArgb(28, 255, 255, 255), Dpi(1f));
        graphics.DrawLine(separator, Dpi(60), railTop + Dpi(14), Dpi(60), railTop + Dpi(50));
    }

    private void DrawFallbackMark(Graphics graphics, RectangleF logoBounds)
    {
        var markBounds = RectangleF.Inflate(logoBounds, -Dpi(10f), -Dpi(9f));
        var strokeWidth = Dpi(3.2f);
        var middleY = markBounds.Top + (markBounds.Height * 0.4f);
        using var markBrush = new LinearGradientBrush(
            markBounds,
            Color.FromArgb(255, 151, 135, 255),
            Color.FromArgb(255, 71, 221, 207),
            45f);
        graphics.FillRectangle(markBrush, markBounds.Left, markBounds.Top, markBounds.Width, strokeWidth);
        graphics.FillRectangle(markBrush, markBounds.Left, markBounds.Top, strokeWidth, markBounds.Height);
        graphics.FillRectangle(markBrush, markBounds.Left, middleY, markBounds.Width * 0.6f, strokeWidth);
    }

    private void DrawWaveform(Graphics graphics, int railTop)
    {
        var accent = GetAccentColor();
        var startX = Dpi(74f);
        var timerLeft = Width - Dpi(116f);
        var maximumEndX = Math.Max(startX + Dpi(28f), timerLeft - Dpi(18f));
        var waveformWidth = Math.Min(Dpi(154f), maximumEndX - startX);
        var gap = waveformWidth / (WaveformBars - 1);
        var centerY = railTop + Dpi(32f);
        var waveformBounds = new RectangleF(
            startX,
            railTop + Dpi(14f),
            waveformWidth + Dpi(3.2f),
            Dpi(36f));
        using var waveformBrush = new LinearGradientBrush(
            waveformBounds,
            Color.FromArgb(105, accent),
            accent,
            LinearGradientMode.Horizontal);
        using var waveformPen = new Pen(waveformBrush, Dpi(3.2f))
        {
            StartCap = LineCap.Round,
            EndCap = LineCap.Round
        };

        for (var index = 0; index < waveform.Length; index++)
        {
            var level = Math.Clamp(waveform[index], 0.03f, 1f);
            var height = Dpi(4f) + (level * Dpi(30f));
            var x = startX + (index * gap);
            graphics.DrawLine(waveformPen, x, centerY - (height / 2f), x, centerY + (height / 2f));
        }
    }

    private void DrawStatus(Graphics graphics, int railTop)
    {
        if (Width < Dpi(430))
        {
            return;
        }

        var stateText = visualState switch
        {
            RecordingOverlayState.Recording when stopControlHovered =>
                "Stop & insert \u00b7 F3",
            RecordingOverlayState.Recording =>
                $"F3 to finish \u00b7 {targetApplication.DisplayName}",
            RecordingOverlayState.Processing => "Finalizing locally",
            RecordingOverlayState.Success => "Inserted",
            RecordingOverlayState.Error => statusMessage,
            _ => string.Empty
        };
        var statusLeft = Dpi(248);
        var statusRight = visualState == RecordingOverlayState.Error
            ? Width - Dpi(58)
            : Width - Dpi(126);
        TextRenderer.DrawText(
            graphics,
            stateText,
            statusFont,
            new Rectangle(
                statusLeft,
                railTop + Dpi(20),
                Math.Max(Dpi(1), statusRight - statusLeft),
                Dpi(24)),
            visualState == RecordingOverlayState.Error
                ? Color.FromArgb(224, 255, 132, 147)
                : Color.FromArgb(158, 214, 216, 226),
            TextFormatFlags.Left |
            TextFormatFlags.VerticalCenter |
            TextFormatFlags.EndEllipsis |
            TextFormatFlags.NoPadding |
            TextFormatFlags.NoPrefix |
            TextFormatFlags.SingleLine);
    }

    private void DrawTimer(Graphics graphics, int railTop)
    {
        if (visualState == RecordingOverlayState.Error)
        {
            return;
        }

        var elapsed = recordingElapsed.Elapsed;
        var timer = $"{(int)elapsed.TotalMinutes:00}:{elapsed.Seconds:00}";
        TextRenderer.DrawText(
            graphics,
            timer,
            timerFont,
            new Rectangle(Width - Dpi(120), railTop + Dpi(20), Dpi(62), Dpi(24)),
            Color.FromArgb(212, 214, 224),
            TextFormatFlags.HorizontalCenter |
            TextFormatFlags.VerticalCenter |
            TextFormatFlags.NoPadding |
            TextFormatFlags.NoPrefix |
            TextFormatFlags.SingleLine);
    }

    private void DrawStateControl(Graphics graphics, int railTop)
    {
        var controlBounds = GetStateControlVisualBounds();
        var controlColor = visualState switch
        {
            RecordingOverlayState.Recording when stopControlPressed => Color.FromArgb(255, 207, 52, 82),
            RecordingOverlayState.Recording when stopControlHovered => Color.FromArgb(255, 247, 88, 118),
            RecordingOverlayState.Success => Color.FromArgb(255, 42, 190, 127),
            RecordingOverlayState.Error => Color.FromArgb(255, 225, 69, 91),
            RecordingOverlayState.Processing => Color.FromArgb(255, 116, 91, 224),
            _ => Color.FromArgb(255, 235, 74, 104)
        };
        if (visualState == RecordingOverlayState.Recording && stopControlHovered)
        {
            using var hoverRing = new Pen(Color.FromArgb(112, 255, 255, 255), Dpi(1.5f));
            graphics.DrawEllipse(
                hoverRing,
                Rectangle.Inflate(controlBounds, Dpi(2), Dpi(2)));
        }
        using var controlBrush = new SolidBrush(controlColor);
        graphics.FillEllipse(controlBrush, controlBounds);

        using var symbolPen = new Pen(Color.White, Dpi(2.3f))
        {
            StartCap = LineCap.Round,
            EndCap = LineCap.Round
        };
        var centerX = Width - Dpi(32);
        switch (visualState)
        {
            case RecordingOverlayState.Recording:
                using (var stopBrush = new SolidBrush(Color.White))
                {
                    graphics.FillRectangle(
                        stopBrush,
                        centerX - Dpi(5),
                        railTop + Dpi(27),
                        Dpi(10),
                        Dpi(10));
                }
                break;
            case RecordingOverlayState.Processing:
                graphics.DrawArc(
                    symbolPen,
                    centerX - Dpi(9),
                    railTop + Dpi(23),
                    Dpi(18),
                    Dpi(18),
                    animationFrame * 11,
                    235);
                break;
            case RecordingOverlayState.Success:
                graphics.DrawLines(symbolPen,
                [
                    new PointF(centerX - Dpi(9f), railTop + Dpi(32f)),
                    new PointF(centerX - Dpi(3f), railTop + Dpi(38f)),
                    new PointF(centerX + Dpi(9f), railTop + Dpi(25f))
                ]);
                break;
            case RecordingOverlayState.Error:
                graphics.DrawLine(
                    symbolPen,
                    centerX,
                    railTop + Dpi(23),
                    centerX,
                    railTop + Dpi(35));
                graphics.DrawEllipse(
                    symbolPen,
                    centerX - Dpi(1),
                    railTop + Dpi(40),
                    Dpi(2),
                    Dpi(2));
                break;
        }
    }

    private Color GetAccentColor()
    {
        return visualState switch
        {
            RecordingOverlayState.Success => Color.FromArgb(255, 70, 220, 155),
            RecordingOverlayState.Error => Color.FromArgb(255, 255, 97, 119),
            RecordingOverlayState.Processing => Color.FromArgb(255, 145, 119, 255),
            _ => Color.FromArgb(255, 117, 132, 255)
        };
    }

    private string GetTranscriptDisplayText()
    {
        if (!string.IsNullOrEmpty(transcript))
        {
            return transcript;
        }

        return visualState switch
        {
            RecordingOverlayState.Recording => "Listening…",
            RecordingOverlayState.Processing => "Transcribing locally…",
            RecordingOverlayState.Success => "Inserted",
            RecordingOverlayState.Error when !string.IsNullOrWhiteSpace(statusMessage) => statusMessage,
            _ => "Listening…"
        };
    }

    private void UpdateTargetApplication(IntPtr targetWindow, bool highlightChange)
    {
        if (targetWindow == IntPtr.Zero)
        {
            return;
        }

        if (targetWindow == displayedTargetWindow)
        {
            var previousWorkingArea = overlayWorkingArea;
            var previousScale = layoutScale;
            UpdateWorkingArea(targetWindow);
            if (overlayWorkingArea != previousWorkingArea ||
                Math.Abs(layoutScale - previousScale) > 0.001f)
            {
                PositionForSize(ClientSize);
                ScheduleTranscriptLayout();
            }
            return;
        }

        var nextTarget = TargetApplicationIdentity.Capture(targetWindow);
        var previousTarget = targetApplication;
        targetApplication = nextTarget;
        displayedTargetWindow = targetWindow;
        previousTarget.Dispose();
        UpdateWorkingArea(targetWindow);

        if (highlightChange)
        {
            targetChangeHighlight = 1f;
            PositionForSize(ClientSize);
        }

        if (visualState == RecordingOverlayState.Recording)
        {
            SetAccessibleDescription(
                string.IsNullOrEmpty(transcript)
                    ? $"FluidVoice Local is listening for {targetApplication.DisplayName}. " +
                      "Live transcript will appear here. Press F3 or click the stop control to finish and insert."
                    : $"FluidVoice Local live local transcript for {targetApplication.DisplayName}: {transcript}");
        }

        Invalidate();
    }

    private static string NormalizeTranscript(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        return string.Join(
            ' ',
            value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
    }

    private void SetAccessibleDescription(
        string? description,
        bool announceStateChange = false)
    {
        var normalized = description ?? string.Empty;
        var changed = !string.Equals(AccessibleDescription, normalized, StringComparison.Ordinal);
        AccessibleDescription = normalized;
        if (!IsHandleCreated)
        {
            return;
        }

        if (changed)
        {
            AccessibilityNotifyClients(AccessibleEvents.DescriptionChange, -1);
        }
        if (announceStateChange)
        {
            AccessibilityNotifyClients(AccessibleEvents.StateChange, -1);
        }
    }

    private static GraphicsPath CreateRoundedPath(RectangleF bounds, float radius)
    {
        var safeRadius = Math.Min(radius, Math.Min(bounds.Width, bounds.Height) / 2f);
        var diameter = safeRadius * 2f;
        var path = new GraphicsPath();
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing && !disposed)
        {
            animationTimer.Stop();
            dismissTimer.Stop();
            transcriptLayoutTimer.Stop();
            animationTimer.Dispose();
            dismissTimer.Dispose();
            transcriptLayoutTimer.Dispose();
            transcript = string.Empty;
            statusMessage = string.Empty;
            InvalidateTranscriptWrap();
            targetApplication.Dispose();
            timerFont.Dispose();
            statusFont.Dispose();
            transcriptFont.Dispose();
            AccessibleDefaultActionDescription = string.Empty;
            AccessibleDescription = string.Empty;
            disposed = true;
        }
        base.Dispose(disposing);
    }

    private Rectangle GetStateControlVisualBounds()
    {
        return new Rectangle(
            Width - Dpi(50),
            Height - Dpi(ControlRailHeight) + Dpi(14),
            Dpi(36),
            Dpi(36));
    }

    private Rectangle GetStateControlHitBounds()
    {
        return Rectangle.Inflate(
            GetStateControlVisualBounds(),
            Dpi(4),
            Dpi(4));
    }

    private void RequestStop()
    {
        if (visualState != RecordingOverlayState.Recording || disposed)
        {
            return;
        }

        if (InvokeRequired)
        {
            BeginInvoke((Action)RequestStop);
            return;
        }

        StopRequested?.Invoke(this, EventArgs.Empty);
    }

    private Rectangle GetScrollbarHitBounds()
    {
        if (lastWrappedLineCount <= lastVisibleLineCapacity || lastVisibleLineCapacity < 1)
        {
            return Rectangle.Empty;
        }

        var railTop = Height - Dpi(ControlRailHeight);
        return new Rectangle(
            Width - Dpi(18),
            Dpi(TranscriptTopPadding),
            Dpi(18),
            Math.Max(1, railTop - Dpi(TranscriptTopPadding + TranscriptBottomPadding)));
    }

    private void ScrollTranscriptTo(int y)
    {
        var bounds = GetScrollbarHitBounds();
        if (bounds.IsEmpty)
        {
            return;
        }

        var maximumOffset = Math.Max(0, lastWrappedLineCount - lastVisibleLineCapacity);
        var progress = Math.Clamp((y - bounds.Top) / (float)Math.Max(1, bounds.Height), 0f, 1f);
        transcriptScrollOffset = (int)Math.Round((1f - progress) * maximumOffset);
        Invalidate();
    }

    private int Dpi(int logicalPixels)
    {
        return Math.Max(1, (int)Math.Round(logicalPixels * layoutScale));
    }

    private float Dpi(float logicalPixels)
    {
        return logicalPixels * layoutScale;
    }

    private Size DpiSize(int width, int height)
    {
        return new Size(Dpi(width), Dpi(height));
    }

    private sealed class RecordingOverlayAccessibleObject : ControlAccessibleObject
    {
        private readonly RecordingOverlayForm owner;

        internal RecordingOverlayAccessibleObject(RecordingOverlayForm owner)
            : base(owner)
        {
            this.owner = owner;
        }

        public override string? Name => owner.AccessibleName;

        public override string? Description => owner.AccessibleDescription;

        public override AccessibleRole Role => AccessibleRole.Pane;

        public override string? DefaultAction => owner.visualState == RecordingOverlayState.Recording
            ? "Stop recording and insert the final transcript"
            : null;

        public override void DoDefaultAction()
        {
            owner.RequestStop();
        }
    }
}
