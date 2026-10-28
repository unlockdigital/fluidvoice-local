using System.Reflection;
using FluidVoice.Hardened;

var assembly = Assembly.Load("FluidVoice Hardened");
var mergerType = assembly.GetType(
    "FluidVoice.Hardened.Windows.LiveTranscriptMerger",
    throwOnError: true)!;
var merge = mergerType.GetMethod(
    "Merge",
    BindingFlags.Static | BindingFlags.NonPublic)!;

var cases = new[]
{
    (
        Previous: "one two three four five six seven eight nine",
        Latest: "three four five six seven eight nine ten eleven",
        Expected: "one two three four five six seven eight nine ten eleven"),
    (
        Previous: "We should meet by the old red door tomorrow morning.",
        Latest: "the old red door tomorrow morning and bring the folder.",
        Expected: "We should meet by the old red door tomorrow morning and bring the folder."),
    (
        Previous: "This is the beginning of a much longer dictation that keeps going",
        Latest: "of a much longer dictation that keeps going with several new words",
        Expected: "This is the beginning of a much longer dictation that keeps going with several new words"),
    (
        Previous: "The first thought ended before a long quiet pause.",
        Latest: "Now a completely new thought is visible.",
        Expected: "The first thought ended before a long quiet pause. Now a completely new thought is visible."),
    (
        Previous: "We will review the proposal with Jordan in the conference room tomorrow morning",
        Latest: "review that revised proposal with Jordan inside the main conference room early tomorrow morning and bring notes",
        Expected: "We will review that revised proposal with Jordan inside the main conference room early tomorrow morning and bring notes")
};

foreach (var test in cases)
{
    var actual = (string)merge.Invoke(null, [test.Previous, test.Latest])!;
    if (!string.Equals(actual, test.Expected, StringComparison.Ordinal))
    {
        Console.Error.WriteLine($"MERGE=FAIL:{actual}");
        return 1;
    }
}

Console.WriteLine($"MERGE=PASS:{cases.Length}");

using (var recorder = new MemoryAudioRecorder())
{
    var recorderType = typeof(MemoryAudioRecorder);
    var previewCapacity = (int)recorderType.GetField(
        "PreviewBufferCapacity",
        BindingFlags.Static | BindingFlags.NonPublic)!.GetRawConstantValue()!;
    recorderType.GetField(
        "previewPcm",
        BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(recorder, new byte[previewCapacity]);
    recorderType.GetField(
        "<IsRecording>k__BackingField",
        BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(recorder, true);
    var append = recorderType.GetMethod(
        "AppendPreviewPcm",
        BindingFlags.Instance | BindingFlags.NonPublic)!;

    var totalSamples = (previewCapacity / sizeof(short)) + 100;
    var pcm = new byte[totalSamples * sizeof(short)];
    for (var index = 0; index < totalSamples; index++)
    {
        var sample = (short)(index % 30_000);
        pcm[index * sizeof(short)] = (byte)(sample & 0xff);
        pcm[(index * sizeof(short)) + 1] = (byte)((sample >> 8) & 0xff);
    }
    append.Invoke(recorder, [pcm, pcm.Length]);

    using var snapshot = recorder.CopySampleSnapshot(TimeSpan.FromSeconds(12))!;
    if (snapshot.FirstSampleIndex != 100 ||
        snapshot.TotalSampleCount != totalSamples ||
        snapshot.Samples.Length != previewCapacity / sizeof(short) ||
        Math.Abs(snapshot.Samples.Span[0] - (100f / 32768f)) > 0.000001f)
    {
        Console.Error.WriteLine("PREVIEW_RING=FAIL");
        return 1;
    }
}

Console.WriteLine("PREVIEW_RING=PASS");
return 0;
