using System.Text;
using Whisper.net;

namespace FluidVoice.Hardened;

public sealed class LocalTranscriber : IDisposable
{
    private readonly WhisperFactory factory;
    private readonly SemaphoreSlim inferenceGate = new(1, 1);
    private bool disposed;

    private LocalTranscriber(WhisperFactory factory)
    {
        this.factory = factory;
    }

    public static async Task<LocalTranscriber> CreateVerifiedAsync(
        string modelPath,
        CancellationToken cancellationToken = default)
    {
        await ModelIntegrity.VerifyAsync(modelPath, cancellationToken).ConfigureAwait(false);
        return new LocalTranscriber(WhisperFactory.FromPath(modelPath));
    }

    public async Task<string> TranscribeAsync(Stream waveStream, CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ArgumentNullException.ThrowIfNull(waveStream);
        await inferenceGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            using var processor = CreateProcessor(livePreview: false);
            var text = new StringBuilder();
            await foreach (var segment in processor.ProcessAsync(waveStream, cancellationToken).ConfigureAwait(false))
            {
                text.Append(segment.Text);
            }

            return text.ToString().Trim();
        }
        finally
        {
            inferenceGate.Release();
        }
    }

    public async Task<string> TranscribeSamplesAsync(
        ReadOnlyMemory<float> samples,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (samples.IsEmpty)
        {
            return string.Empty;
        }

        await inferenceGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            using var processor = CreateProcessor(livePreview: true);
            var text = new StringBuilder();
            await foreach (var segment in processor.ProcessAsync(samples, cancellationToken).ConfigureAwait(false))
            {
                text.Append(segment.Text);
            }

            return text.ToString().Trim();
        }
        finally
        {
            inferenceGate.Release();
        }
    }

    private WhisperProcessor CreateProcessor(bool livePreview)
    {
        var builder = factory.CreateBuilder()
            .WithLanguage("en");
        if (livePreview)
        {
            builder.WithMaxSegmentLength(96)
                .SplitOnWord();
        }

        return builder.Build();
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        inferenceGate.Wait();
        try
        {
            factory.Dispose();
        }
        finally
        {
            inferenceGate.Release();
            inferenceGate.Dispose();
        }
        GC.SuppressFinalize(this);
    }
}
