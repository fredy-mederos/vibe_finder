import Foundation

/// A few items enrichment just finished, with how far it is.
public struct EnrichmentBatch: Sendable {
    public var items: [FileItem]
    public var completed: Int
    public var total: Int

    public init(items: [FileItem], completed: Int, total: Int) {
        self.items = items
        self.completed = completed
        self.total = total
    }
}

/// Looks inside the files a scan left pending: runs each through the steps that apply to it, stores
/// what they found (so it's only done once per version of a file) and reports the items as they change.
public struct EnrichLibrary: EnrichmentPlanning {
    private let enrichers: [any ItemEnricher]
    private let cache: any EnrichmentCaching
    /// Files looked into at the same time.
    private let concurrency: Int
    private static let batchSize = 24
    private static let batchInterval: Duration = .milliseconds(700)

    public init(enrichers: [any ItemEnricher], cache: any EnrichmentCaching, concurrency: Int = 3) {
        self.enrichers = enrichers
        self.cache = cache
        self.concurrency = max(1, concurrency)
    }

    /// The steps the settings allow and that can run right now.
    private func activeEnrichers(for settings: LibrarySettings) -> [any ItemEnricher] {
        let disabled = settings.disabledStages
        return enrichers.filter { disabled.isDisjoint(with: $0.stage) && $0.isAvailable }
    }

    public func needsEnrichment(_ item: FileItem, cached: CachedEnrichment?, settings: LibrarySettings) -> Bool {
        let active = activeEnrichers(for: settings)
        guard active.contains(where: { $0.applies(to: item) }) else { return false }
        guard let cached else { return true }
        return !cached.stages.isSuperset(of: Self.stages(of: active))
    }

    /// Enriches the items in order, a few at a time, until done or until the stream's consumer stops.
    public func run(_ items: [FileItem], settings: LibrarySettings) -> AsyncStream<EnrichmentBatch> {
        let active = activeEnrichers(for: settings)
        let stages = Self.stages(of: active)
        let (cache, concurrency) = (cache, concurrency)
        return AsyncStream { continuation in
            let task = Task(priority: .utility) {
                var batch: [EnrichmentRecord] = []
                var completed = 0
                var lastFlush = ContinuousClock.now
                await withTaskGroup(of: EnrichmentRecord?.self) { group in
                    var remaining = items.makeIterator()
                    for _ in 0..<concurrency {
                        guard let item = remaining.next() else { break }
                        group.addTask { await Self.process(item, with: active, stages: stages) }
                    }
                    while let record = await group.next() {
                        if Task.isCancelled {
                            group.cancelAll()
                            break
                        }
                        completed += 1
                        if let record { batch.append(record) }
                        if batch.count >= Self.batchSize || ContinuousClock.now - lastFlush >= Self.batchInterval {
                            Self.flush(&batch, to: cache, continuation, completed: completed, total: items.count)
                            lastFlush = .now
                        }
                        if let item = remaining.next() {
                            group.addTask { await Self.process(item, with: active, stages: stages) }
                        }
                    }
                }
                Self.flush(&batch, to: cache, continuation, completed: completed, total: items.count)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func stages(of enrichers: [any ItemEnricher]) -> EnrichmentStages {
        enrichers.reduce(into: EnrichmentStages()) { $0.formUnion($1.stage) }
    }

    private static func flush(_ batch: inout [EnrichmentRecord], to cache: any EnrichmentCaching,
                              _ continuation: AsyncStream<EnrichmentBatch>.Continuation, completed: Int, total: Int) {
        guard !batch.isEmpty else { return }
        cache.save(batch)
        continuation.yield(EnrichmentBatch(items: batch.map(\.item), completed: completed, total: total))
        batch.removeAll(keepingCapacity: true)
    }

    /// One item through every step that applies; nil when it was interrupted (and so isn't stored).
    private static func process(_ item: FileItem, with enrichers: [any ItemEnricher], stages: EnrichmentStages) async -> EnrichmentRecord? {
        var draft = EnrichmentDraft(item: item)
        for enricher in enrichers where enricher.applies(to: draft.item) {
            if Task.isCancelled { return nil }
            await enricher.enrich(&draft)
        }
        return EnrichmentRecord(item: draft.item, stages: stages, text: draft.text)
    }
}
