import Foundation

/// Media auto-pause is excluded from FluidVoice Local.
///
/// The former implementation loaded a private MediaRemote adapter through a Perl child
/// process and a separately signed dynamic framework. Dictation does not require that path.
/// Keeping this API as a no-op preserves the ASR session flow while removing the framework,
/// child-process, and private-framework surface from the hardened application.
@MainActor
final class MediaPlaybackService {
    static let shared = MediaPlaybackService()

    private init() {}

    func pauseIfPlaying() async -> Bool {
        false
    }

    func resumeIfWePaused(_ wePaused: Bool) async {
        _ = wePaused
    }
}
