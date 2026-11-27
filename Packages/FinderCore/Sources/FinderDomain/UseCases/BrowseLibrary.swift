import Foundation

/// Turns the library into what one screen shows: the items of a kind (or the matches of a search),
/// ordered and split into sections.
public struct ArrangeItems: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func execute(_ items: [FileItem], request: BrowseRequest, now: Date = Date()) -> BrowseResult {
        var matches = items
        if let kind = request.kind {
            matches = matches.filter { $0.kind == kind }
        }
        if !request.terms.isEmpty {
            matches = matches.filter { item in
                request.contentMatches.contains(item.path) || request.terms.allSatisfy { item.folded.contains($0) }
            }
        }
        let subkinds = Self.subkindCounts(matches)
        if let subkind = request.subkind {
            matches = matches.filter { $0.subkind == subkind }
        }
        let sections: [ItemSection]
        if request.kind == nil {
            // Everything at once is only shown for a search: by kind, in the sidebar's order.
            let byKind = Dictionary(grouping: matches, by: \.kind)
            sections = Kind.allCases.compactMap { kind in
                byKind[kind].map { ItemSection(key: .kind(kind), items: sorted($0, by: request.arrangement)) }
            }
        } else {
            sections = arrange(matches, by: request.arrangement, now: now)
        }
        return BrowseResult(sections: sections, count: matches.count, subkinds: subkinds)
    }

    // MARK: - Arranging

    private func arrange(_ items: [FileItem], by arrangement: Arrangement, now: Date) -> [ItemSection] {
        guard !items.isEmpty else { return [] }
        let ordered = sorted(items, by: arrangement)
        switch arrangement {
        case .name, .size:
            return [ItemSection(key: .all, items: ordered)]
        case .date:
            return runs(ordered) { period(of: $0.modified, now: now) }
        case .type:
            let groups = Dictionary(grouping: ordered, by: \.subkind)
            return groups.sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
                .map { ItemSection(key: .subkind($0.key), items: $0.value) }
        case .folder:
            let groups = Dictionary(grouping: ordered, by: \.folder)
            return groups.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                .map { ItemSection(key: .folder($0.key), items: $0.value) }
        }
    }

    private func sorted(_ items: [FileItem], by arrangement: Arrangement) -> [FileItem] {
        switch arrangement {
        case .date, .type:
            items.sorted { ($0.modified, $1.path) > ($1.modified, $0.path) }
        case .name, .folder:
            items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            items.sorted { ($0.size, $1.path) > ($1.size, $0.path) }
        }
    }

    /// Splits an ordered list where the key changes.
    private func runs(_ items: [FileItem], key: (FileItem) -> SectionKey) -> [ItemSection] {
        var sections: [ItemSection] = []
        for item in items {
            let itemKey = key(item)
            if sections.last?.key == itemKey {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(ItemSection(key: itemKey, items: [item]))
            }
        }
        return sections
    }

    /// Recent days get their own sections, then the months of this year, then whole years.
    private func period(of date: Date, now: Date) -> SectionKey {
        let today = calendar.startOfDay(for: now)
        if date >= today { return .today }
        if let week = calendar.date(byAdding: .day, value: -7, to: today), date >= week { return .previous7Days }
        if let month = calendar.date(byAdding: .day, value: -30, to: today), date >= month { return .previous30Days }
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 0
        return year == calendar.component(.year, from: now) ? .month(year: year, month: parts.month ?? 1) : .year(year)
    }

    static func subkindCounts(_ items: [FileItem]) -> [SubkindCount] {
        var counts: [String: Int] = [:]
        for item in items { counts[item.subkind, default: 0] += 1 }
        return counts.map { SubkindCount(name: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }
}

/// What there is of each kind: how many, how big, the subkinds and the latest few.
public struct SummarizeLibrary: Sendable {
    private let recentCount: Int

    public init(recentCount: Int = 8) {
        self.recentCount = recentCount
    }

    public func execute(_ items: [FileItem]) -> LibrarySummary {
        var summary = LibrarySummary()
        for (kind, group) in Dictionary(grouping: items, by: \.kind) {
            let size = group.reduce(Int64(0)) { $0 + $1.size }
            let recent = group.sorted { ($0.modified, $1.path) > ($1.modified, $0.path) }.prefix(recentCount)
            summary.kinds[kind] = KindSummary(kind: kind, count: group.count, size: size,
                                              subkinds: ArrangeItems.subkindCounts(group), recent: Array(recent))
            summary.count += group.count
            summary.size += size
        }
        return summary
    }
}

/// Which items the library shows: what's inside code projects stays out unless the user wants it.
public struct VisibleItems: Sendable {
    public init() {}

    public func execute(_ items: [FileItem], settings: LibrarySettings) -> [FileItem] {
        settings.includesProjectFiles ? items : items.filter { !$0.inProject }
    }
}

/// Finds files by the text inside them.
public struct SearchContent: Sendable {
    private let index: any ContentSearching
    private let limit: Int

    public init(index: any ContentSearching, limit: Int = 500) {
        self.index = index
        self.limit = limit
    }

    /// The snippet around the match for each file found. Blocking: call it off the main thread.
    public func execute(_ text: String) -> [String: String] {
        let terms = SearchTerms.parse(text)
        guard !terms.isEmpty else { return [:] }
        var snippets: [String: String] = [:]
        for hit in index.search(terms: terms, limit: limit) { snippets[hit.path] = hit.snippet }
        return snippets
    }
}
