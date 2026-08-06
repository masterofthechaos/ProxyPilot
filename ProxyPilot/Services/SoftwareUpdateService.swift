import Combine
import Foundation
import Sparkle

@MainActor
enum SoftwareUpdateChannelPolicy {
    static let alphaChannel = "alpha"

    static func allowedChannels(isAlphaBuild: Bool) -> Set<String> {
        isAlphaBuild ? [alphaChannel] : []
    }
}

@MainActor
final class SoftwareUpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published var canCheckForUpdates = false

    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }()

    private var cancellables: Set<AnyCancellable> = []
    private var didRunLaunchBackgroundCheck = false

    override init() {
        super.init()

        let updater = updaterController.updater
        updater.automaticallyChecksForUpdates = true

        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] canCheck in
                guard let self else { return }
                self.canCheckForUpdates = canCheck
                self.runLaunchBackgroundCheckIfNeeded()
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }

    func checkForUpdatesInBackground() {
        runLaunchBackgroundCheckIfNeeded()
    }

    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        MainActor.assumeIsolated {
            SoftwareUpdateChannelPolicy.allowedChannels(
                isAlphaBuild: AppBuildBadge.current != nil
            )
        }
    }

    private func runLaunchBackgroundCheckIfNeeded() {
        guard !didRunLaunchBackgroundCheck else { return }
        guard canCheckForUpdates else { return }
        didRunLaunchBackgroundCheck = true
        updaterController.updater.checkForUpdatesInBackground()
    }
}
