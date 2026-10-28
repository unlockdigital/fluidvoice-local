using System.Security.Cryptography;
using FluidVoice.Hardened;
using NAudio.Wave;

if (args.Length is < 1 or > 3)
{
    Console.Error.WriteLine("Usage: FluidVoice.Verify <model-path> [synthetic-wav-path | --capture seconds]");
    return 64;
}

try
{
    await ModelIntegrity.VerifyAsync(args[0]);
    Console.WriteLine($"MODEL_SHA256=PASS:{SecureProfile.ModelSha256}");
    Console.WriteLine($"MICROPHONE_CAPTURE_DEVICES={MemoryAudioRecorder.CaptureDeviceCount}");

    using var transcriber = await LocalTranscriber.CreateVerifiedAsync(args[0]);
    Console.WriteLine("MODEL_LOAD=PASS");

    if (args.Length == 3 && string.Equals(args[1], "--capture", StringComparison.Ordinal))
    {
        if (!int.TryParse(args[2], out var seconds) || seconds is < 1 or > 60)
        {
            Console.Error.WriteLine("Capture seconds must be between 1 and 60.");
            return 64;
        }

        using var recorder = new MemoryAudioRecorder();
        recorder.Start();
        Console.WriteLine("MICROPHONE_CAPTURE=STARTED");
        await Task.Delay(TimeSpan.FromSeconds(seconds));
        var captured = await recorder.StopAsync();
        try
        {
            await using var audio = new MemoryStream(captured, writable: false);
            var transcript = await transcriber.TranscribeAsync(audio);
            Console.WriteLine($"CAPTURE_TRANSCRIPT={transcript}");
            Console.WriteLine(string.IsNullOrWhiteSpace(transcript) ? "MICROPHONE_ASR=FAIL" : "MICROPHONE_ASR=PASS");
            return string.IsNullOrWhiteSpace(transcript) ? 1 : 0;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(captured);
        }
    }

    if (args.Length == 2)
    {
        await using var audio = File.OpenRead(args[1]);
        var transcript = await transcriber.TranscribeAsync(audio);
        Console.WriteLine($"SYNTHETIC_TRANSCRIPT={transcript}");
        var finalPassed = !string.IsNullOrWhiteSpace(transcript);
        Console.WriteLine(finalPassed ? "SYNTHETIC_ASR=PASS" : "SYNTHETIC_ASR=FAIL");

        var samples = ReadPreviewSamples(args[1]);
        try
        {
            var previewTranscript = await transcriber.TranscribeSamplesAsync(samples);
            Console.WriteLine($"PREVIEW_TRANSCRIPT={previewTranscript}");
            var previewPassed = !string.IsNullOrWhiteSpace(previewTranscript);
            Console.WriteLine(previewPassed ? "PREVIEW_ASR=PASS" : "PREVIEW_ASR=FAIL");
            return finalPassed && previewPassed ? 0 : 1;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(
                System.Runtime.InteropServices.MemoryMarshal.AsBytes(samples.AsSpan()));
        }
    }

    return 0;
}
catch (Exception error)
{
    Console.Error.WriteLine($"VERIFY=FAIL:{error.GetType().Name}:{error.Message}");
    return 1;
}

static float[] ReadPreviewSamples(string wavePath)
{
    using var reader = new WaveFileReader(wavePath);
    if (reader.WaveFormat.Encoding != WaveFormatEncoding.Pcm ||
        reader.WaveFormat.SampleRate != 16_000 ||
        reader.WaveFormat.BitsPerSample != 16 ||
        reader.WaveFormat.Channels != 1)
    {
        throw new InvalidOperationException("Preview verification requires 16 kHz, 16-bit, mono PCM WAV input.");
    }

    var pcm = new byte[checked((int)reader.Length)];
    try
    {
        var totalBytes = 0;
        while (totalBytes < pcm.Length)
        {
            var bytesRead = reader.Read(pcm, totalBytes, pcm.Length - totalBytes);
            if (bytesRead == 0)
            {
                break;
            }
            totalBytes += bytesRead;
        }

        var samples = new float[totalBytes / sizeof(short)];
        for (var index = 0; index < samples.Length; index++)
        {
            var offset = index * sizeof(short);
            var sample = (short)(pcm[offset] | (pcm[offset + 1] << 8));
            samples[index] = sample / 32768f;
        }
        return samples;
    }
    finally
    {
        CryptographicOperations.ZeroMemory(pcm);
    }
}
