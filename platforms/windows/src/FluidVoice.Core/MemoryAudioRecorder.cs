using NAudio.Wave;
using System.Security.Cryptography;
using System.Runtime.InteropServices;

namespace FluidVoice.Hardened;

public sealed class AudioSampleSnapshot : IDisposable
{
    private float[] samples;

    internal AudioSampleSnapshot(float[] samples, long firstSampleIndex, long totalSampleCount)
    {
        this.samples = samples;
        FirstSampleIndex = firstSampleIndex;
        TotalSampleCount = totalSampleCount;
    }

    public ReadOnlyMemory<float> Samples => samples;

    public long FirstSampleIndex { get; }

    public long TotalSampleCount { get; }

    public void Dispose()
    {
        if (samples.Length == 0)
        {
            return;
        }

        CryptographicOperations.ZeroMemory(MemoryMarshal.AsBytes(samples.AsSpan()));
        samples = [];
        GC.SuppressFinalize(this);
    }
}

public sealed class MemoryAudioRecorder : IDisposable
{
    private const int SampleRate = 16_000;
    private const int BytesPerSample = sizeof(short);
    private const int PreviewBufferSeconds = 12;
    private const int PreviewBufferCapacity = SampleRate * BytesPerSample * PreviewBufferSeconds;

    private readonly object sync = new();
    private WaveInEvent? capture;
    private MemoryStream? buffer;
    private byte[]? previewPcm;
    private WaveFileWriter? writer;
    private TaskCompletionSource? stopped;
    private int previewWriteOffset;
    private int previewByteCount;
    private long totalPreviewBytes;
    private bool disposed;

    public static int CaptureDeviceCount => WaveInEvent.DeviceCount;

    public event Action<float>? AudioLevelChanged;

    public bool IsRecording { get; private set; }

    public void Start()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (IsRecording)
        {
            throw new InvalidOperationException("Recording is already active.");
        }

        if (CaptureDeviceCount < 1)
        {
            throw new InvalidOperationException("Windows reports no microphone capture device.");
        }

        buffer = new MemoryStream(capacity: 1024 * 1024);
        previewPcm = new byte[PreviewBufferCapacity];
        previewWriteOffset = 0;
        previewByteCount = 0;
        totalPreviewBytes = 0;
        capture = new WaveInEvent
        {
            DeviceNumber = 0,
            WaveFormat = new WaveFormat(SampleRate, 16, 1),
            BufferMilliseconds = 50,
            NumberOfBuffers = 3
        };
        writer = new WaveFileWriter(buffer, capture.WaveFormat);
        stopped = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        capture.DataAvailable += OnDataAvailable;
        capture.RecordingStopped += OnRecordingStopped;
        IsRecording = true;

        try
        {
            capture.StartRecording();
        }
        catch
        {
            IsRecording = false;
            CleanupCapture();
            throw;
        }
    }

    public async Task<byte[]> StopAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (!IsRecording || capture is null || buffer is null || writer is null || stopped is null)
        {
            throw new InvalidOperationException("Recording is not active.");
        }

        IsRecording = false;
        var completed = false;
        try
        {
            capture.StopRecording();
            await stopped.Task.WaitAsync(TimeSpan.FromSeconds(5), cancellationToken).ConfigureAwait(false);

            lock (sync)
            {
                writer.Dispose();
                writer = null;
                var audio = buffer.ToArray();
                if (buffer.TryGetBuffer(out var segment) && segment.Array is not null)
                {
                    CryptographicOperations.ZeroMemory(segment.Array.AsSpan(segment.Offset, segment.Count));
                }
                buffer.Dispose();
                buffer = null;
                CleanupCapture();
                completed = true;
                return audio;
            }
        }
        finally
        {
            if (!completed)
            {
                lock (sync)
                {
                    CleanupCapture();
                }
            }
        }
    }

    public AudioSampleSnapshot? CopySampleSnapshot(TimeSpan maximumDuration)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (maximumDuration <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumDuration));
        }

        lock (sync)
        {
            if (!IsRecording || previewPcm is null || previewByteCount < BytesPerSample)
            {
                return null;
            }

            var totalSampleCount = totalPreviewBytes / BytesPerSample;
            var maximumSampleCount = Math.Max(1L, (long)(maximumDuration.TotalSeconds * SampleRate));
            var availableSampleCount = previewByteCount / BytesPerSample;
            var sampleCount = checked((int)Math.Min(availableSampleCount, maximumSampleCount));
            var firstSampleIndex = totalSampleCount - sampleCount;
            var samples = new float[sampleCount];
            var oldestOffset = (previewWriteOffset - previewByteCount + previewPcm.Length) % previewPcm.Length;
            var skippedBytes = previewByteCount - (sampleCount * BytesPerSample);
            var byteOffset = (oldestOffset + skippedBytes) % previewPcm.Length;
            for (var index = 0; index < sampleCount; index++)
            {
                var low = previewPcm[byteOffset];
                byteOffset = (byteOffset + 1) % previewPcm.Length;
                var high = previewPcm[byteOffset];
                byteOffset = (byteOffset + 1) % previewPcm.Length;
                var sample = (short)(low | (high << 8));
                samples[index] = sample / 32768f;
            }

            return new AudioSampleSnapshot(samples, firstSampleIndex, totalSampleCount);
        }
    }

    public void Abort()
    {
        if (capture is not null && IsRecording)
        {
            IsRecording = false;
            capture.StopRecording();
        }

        lock (sync)
        {
            CleanupCapture();
        }
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs args)
    {
        var level = CalculateRootMeanSquare(args.Buffer, args.BytesRecorded);
        lock (sync)
        {
            if (IsRecording && writer is not null)
            {
                writer.Write(args.Buffer, 0, args.BytesRecorded);
                AppendPreviewPcm(args.Buffer, args.BytesRecorded);
            }
        }
        AudioLevelChanged?.Invoke(level);
    }

    private void AppendPreviewPcm(byte[] source, int bytesRecorded)
    {
        if (previewPcm is null || bytesRecorded <= 0)
        {
            return;
        }

        totalPreviewBytes += bytesRecorded;
        var bytesToCopy = Math.Min(bytesRecorded, previewPcm.Length);
        var sourceOffset = bytesRecorded - bytesToCopy;
        var firstCopy = Math.Min(bytesToCopy, previewPcm.Length - previewWriteOffset);
        Buffer.BlockCopy(source, sourceOffset, previewPcm, previewWriteOffset, firstCopy);
        var secondCopy = bytesToCopy - firstCopy;
        if (secondCopy > 0)
        {
            Buffer.BlockCopy(source, sourceOffset + firstCopy, previewPcm, 0, secondCopy);
        }

        previewWriteOffset = (previewWriteOffset + bytesToCopy) % previewPcm.Length;
        previewByteCount = Math.Min(previewPcm.Length, previewByteCount + bytesToCopy);
    }

    private static float CalculateRootMeanSquare(byte[] audio, int bytesRecorded)
    {
        var sampleCount = bytesRecorded / sizeof(short);
        if (sampleCount == 0)
        {
            return 0;
        }

        double sumOfSquares = 0;
        for (var offset = 0; offset + 1 < bytesRecorded; offset += sizeof(short))
        {
            var sample = (short)(audio[offset] | (audio[offset + 1] << 8));
            var normalized = sample / 32768d;
            sumOfSquares += normalized * normalized;
        }

        return (float)Math.Clamp(Math.Sqrt(sumOfSquares / sampleCount), 0d, 1d);
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs args)
    {
        if (args.Exception is null)
        {
            stopped?.TrySetResult();
        }
        else
        {
            stopped?.TrySetException(args.Exception);
        }
    }

    private void CleanupCapture()
    {
        if (capture is not null)
        {
            capture.DataAvailable -= OnDataAvailable;
            capture.RecordingStopped -= OnRecordingStopped;
            capture.Dispose();
            capture = null;
        }

        writer?.Dispose();
        writer = null;

        if (buffer is not null)
        {
            if (buffer.TryGetBuffer(out var segment) && segment.Array is not null)
            {
                CryptographicOperations.ZeroMemory(segment.Array.AsSpan(segment.Offset, segment.Count));
            }
            buffer.Dispose();
            buffer = null;
        }

        if (previewPcm is not null)
        {
            CryptographicOperations.ZeroMemory(previewPcm);
            previewPcm = null;
        }
        previewWriteOffset = 0;
        previewByteCount = 0;
        totalPreviewBytes = 0;
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        Abort();
        disposed = true;
        GC.SuppressFinalize(this);
    }
}
