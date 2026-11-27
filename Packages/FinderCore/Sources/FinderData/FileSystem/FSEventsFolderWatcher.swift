import Foundation
import CoreServices
import FinderDomain

/// Watches folders with FSEvents and reports once per burst of changes that could matter to the
/// index: changes inside what a scan skips (a build running in a project, a .git folder) are ignored.
public final class FSEventsFolderWatcher: FolderWatching, @unchecked Sendable {
    private let policy: ScanPolicy
    /// Seconds FSEvents waits to gather changes into one report.
    private let latency: TimeInterval
    // The stream and its handler are only touched under `lock`.
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var onChange: (@Sendable () -> Void)?
    private let queue = DispatchQueue(label: "com.fredymederos.VibeFinder.folder-watcher", qos: .utility)

    public init(policy: ScanPolicy = .standard, latency: TimeInterval = 3) {
        self.policy = policy
        self.latency = latency
    }

    deinit {
        stop()
    }

    public func watch(_ folders: [String], onChange: @escaping @Sendable () -> Void) {
        stop()
        guard !folders.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info, let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
            Unmanaged<FSEventsFolderWatcher>.fromOpaque(info).takeUnretainedValue().handle(Array(paths.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(nil, callback, &context, folders as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        lock.withLock {
            self.stream = stream
            self.onChange = onChange
        }
    }

    public func stop() {
        lock.lock()
        let stream = self.stream
        self.stream = nil
        onChange = nil
        lock.unlock()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func handle(_ paths: [String]) {
        guard paths.contains(where: { !policy.ignoresChange(at: $0) }) else { return }
        lock.withLock { onChange }?()
    }
}
