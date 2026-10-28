using System.Security.Cryptography;

namespace FluidVoice.Hardened;

public static class ModelIntegrity
{
    public static async Task VerifyAsync(string modelPath, CancellationToken cancellationToken = default)
    {
        var file = new FileInfo(modelPath);
        if (!file.Exists)
        {
            throw new FileNotFoundException("The approved local speech model is missing.", modelPath);
        }

        if (file.Length != SecureProfile.ModelBytes)
        {
            throw new InvalidDataException($"Model size mismatch. Expected {SecureProfile.ModelBytes} bytes, found {file.Length}.");
        }

        await using var stream = new FileStream(
            modelPath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            bufferSize: 1024 * 1024,
            options: FileOptions.Asynchronous | FileOptions.SequentialScan);

        var hash = await SHA256.HashDataAsync(stream, cancellationToken).ConfigureAwait(false);
        var actual = Convert.ToHexStringLower(hash);
        CryptographicOperations.ZeroMemory(hash);

        if (!string.Equals(actual, SecureProfile.ModelSha256, StringComparison.Ordinal))
        {
            throw new CryptographicException("The local speech model failed SHA-256 verification and will not be loaded.");
        }
    }
}
