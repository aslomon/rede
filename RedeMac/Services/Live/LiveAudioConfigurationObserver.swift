import AVFoundation

@MainActor final class LiveAudioConfigurationObserver {
    private let center: NotificationCenter
    private var token: NSObjectProtocol?
    private var generation = 0

    init(center: NotificationCenter = .default) { self.center = center }

    func start(object: AnyObject, onFailure: @escaping @MainActor (LiveFailure) -> Void) {
        stop()
        let run = generation
        token = center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: object, queue: nil
        ) { [weak self] _ in
            // Apple forbids tearing down the engine synchronously on this internal callback queue.
            Task { @MainActor [weak self] in
                guard let self, generation == run else { return }
                stop()
                onFailure(.captureFailed)
            }
        }
    }

    func stop() {
        generation += 1
        if let token { center.removeObserver(token) }
        token = nil
    }

    deinit { if let token { center.removeObserver(token) } }
}
