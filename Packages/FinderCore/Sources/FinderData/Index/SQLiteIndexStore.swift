import Foundation
import SQLite3
import FinderDomain

/// The index on disk: what enrichment learned about each file, and the text found in them in a
/// full-text table (FTS5) for content search. One SQLite file in the app's data folder; it only ever
/// holds things that can be rebuilt from the user's folders.
public final class SQLiteIndexStore: EnrichmentCaching, ContentSearching, IndexedTextReading, @unchecked Sendable {
    // Every use of the connection goes through `lock`.
    private let lock = NSLock()
    private var database: OpaquePointer?

    /// Bumped when the stored shape changes; an older index is dropped and rebuilt.
    private static let schemaVersion = 4
    /// Text longer than this is cut: enough to find a document by what it says near its start.
    private static let maxTextLength = 200_000
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// - Parameters:
    ///   - directory: where `index.sqlite` lives; created if needed.
    ///   - rulesVersion: the version of the rules whose answers are stored; an index made with other
    ///     rules is dropped, so every file is looked at again with the current ones.
    public init(directory: URL, rulesVersion: Int = EnrichmentRules.version) {
        let version = Int32(Self.schemaVersion * 10_000 + rulesVersion)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("index.sqlite").path
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            database = nil
            return
        }
        execute("PRAGMA journal_mode = WAL")
        execute("PRAGMA synchronous = NORMAL")
        let stored = Int(userVersion())
        let (storedSchema, storedRules) = (stored / 10_000, stored % 10_000)
        if storedRules != rulesVersion || !(1...Self.schemaVersion).contains(storedSchema) {
            execute("DROP TABLE IF EXISTS files")
            execute("DROP TABLE IF EXISTS content")
            execute("DROP TABLE IF EXISTS summaries")
        } else {
            // Later versions only added columns; what an earlier one learned is still good.
            if storedSchema < 2 { execute("ALTER TABLE files ADD COLUMN artwork TEXT") }
            if storedSchema < 3 { execute("ALTER TABLE files ADD COLUMN measured_size INTEGER") }
            if storedSchema < 4 { execute("ALTER TABLE files ADD COLUMN summary TEXT") }
        }
        execute("PRAGMA user_version = \(version)")
        execute("""
            CREATE TABLE IF NOT EXISTS files(
                id INTEGER PRIMARY KEY,
                path TEXT NOT NULL UNIQUE,
                size INTEGER NOT NULL,
                modified REAL NOT NULL,
                kind TEXT NOT NULL,
                subkind TEXT NOT NULL,
                source INTEGER NOT NULL,
                unclear INTEGER NOT NULL,
                detail TEXT NOT NULL,
                stages INTEGER NOT NULL,
                artwork TEXT,
                measured_size INTEGER,
                summary TEXT
            )
            """)
        // rowid is the file's id. Diacritics are folded so "factura" finds "Factúra".
        execute("CREATE VIRTUAL TABLE IF NOT EXISTS content USING fts5(body, tokenize = 'unicode61 remove_diacritics 2')")
        // The one-line descriptions, searched like the text but kept apart from it: a file's own words
        // and the words written about it are different things to show.
        execute("CREATE VIRTUAL TABLE IF NOT EXISTS summaries USING fts5(body, tokenize = 'unicode61 remove_diacritics 2')")
    }

    deinit {
        sqlite3_close_v2(database)
    }

    // MARK: - EnrichmentCaching

    public func loadAll() -> [String: CachedEnrichment] {
        lock.withLock {
            var rows: [String: CachedEnrichment] = [:]
            query("SELECT path, size, modified, kind, subkind, source, unclear, detail, stages, artwork, measured_size, summary FROM files") { statement in
                guard let kind = Kind(rawValue: Self.text(statement, 3)),
                      let source = ClassificationSource(rawValue: Int(sqlite3_column_int(statement, 5))) else { return }
                rows[Self.text(statement, 0)] = CachedEnrichment(
                    size: sqlite3_column_int64(statement, 1),
                    modified: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 2)),
                    classification: Classification(kind: kind, subkind: Self.text(statement, 4), source: source,
                                                   isUnclear: sqlite3_column_int(statement, 6) != 0),
                    detail: Self.text(statement, 7),
                    artworkPath: sqlite3_column_text(statement, 9).map { String(cString: $0) },
                    measuredSize: sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 10),
                    summary: sqlite3_column_text(statement, 11).map { String(cString: $0) },
                    stages: EnrichmentStages(rawValue: Int(sqlite3_column_int64(statement, 8)))
                )
            }
            return rows
        }
    }

    public func save(_ records: [EnrichmentRecord]) {
        guard !records.isEmpty else { return }
        lock.withLock {
            execute("BEGIN")
            let upsert = prepare("""
                INSERT INTO files(path, size, modified, kind, subkind, source, unclear, detail, stages, artwork, measured_size, summary)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET size = excluded.size, modified = excluded.modified, kind = excluded.kind,
                    subkind = excluded.subkind, source = excluded.source, unclear = excluded.unclear,
                    detail = excluded.detail, stages = excluded.stages, artwork = excluded.artwork,
                    measured_size = excluded.measured_size, summary = excluded.summary
                RETURNING id
                """)
            let removeText = prepare("DELETE FROM content WHERE rowid = ?")
            let insertText = prepare("INSERT INTO content(rowid, body) VALUES(?, ?)")
            let removeSummary = prepare("DELETE FROM summaries WHERE rowid = ?")
            let insertSummary = prepare("INSERT INTO summaries(rowid, body) VALUES(?, ?)")
            for record in records {
                let item = record.item
                sqlite3_reset(upsert)
                Self.bind(upsert, 1, item.path)
                sqlite3_bind_int64(upsert, 2, item.size)
                sqlite3_bind_double(upsert, 3, item.modified.timeIntervalSinceReferenceDate)
                Self.bind(upsert, 4, item.kind.rawValue)
                Self.bind(upsert, 5, item.subkind)
                sqlite3_bind_int(upsert, 6, Int32(item.source.rawValue))
                sqlite3_bind_int(upsert, 7, item.isUnclear ? 1 : 0)
                Self.bind(upsert, 8, item.detail)
                sqlite3_bind_int64(upsert, 9, Int64(record.stages.rawValue))
                if let artwork = item.artworkPath {
                    Self.bind(upsert, 10, artwork)
                } else {
                    sqlite3_bind_null(upsert, 10)
                }
                if let measuredSize = item.measuredSize {
                    sqlite3_bind_int64(upsert, 11, measuredSize)
                } else {
                    sqlite3_bind_null(upsert, 11)
                }
                if let summary = item.summary {
                    Self.bind(upsert, 12, summary)
                } else {
                    sqlite3_bind_null(upsert, 12)
                }
                guard sqlite3_step(upsert) == SQLITE_ROW else { continue }
                let id = sqlite3_column_int64(upsert, 0)
                sqlite3_reset(upsert)

                // Text is only touched when a step read it this time; otherwise what's stored stands.
                if case .replace(let text) = record.text {
                    sqlite3_reset(removeText)
                    sqlite3_bind_int64(removeText, 1, id)
                    sqlite3_step(removeText)
                    if let text, !text.isEmpty {
                        sqlite3_reset(insertText)
                        sqlite3_bind_int64(insertText, 1, id)
                        Self.bind(insertText, 2, String(text.prefix(Self.maxTextLength)))
                        sqlite3_step(insertText)
                    }
                }
                sqlite3_reset(removeSummary)
                sqlite3_bind_int64(removeSummary, 1, id)
                sqlite3_step(removeSummary)
                if let summary = item.summary, !summary.isEmpty {
                    sqlite3_reset(insertSummary)
                    sqlite3_bind_int64(insertSummary, 1, id)
                    Self.bind(insertSummary, 2, summary)
                    sqlite3_step(insertSummary)
                }
            }
            for statement in [upsert, removeText, insertText, removeSummary, insertSummary] { sqlite3_finalize(statement) }
            execute("COMMIT")
        }
    }

    public func prune(keeping paths: Set<String>) {
        lock.withLock {
            var gone: [Int64] = []
            query("SELECT id, path FROM files") { statement in
                if !paths.contains(Self.text(statement, 1)) { gone.append(sqlite3_column_int64(statement, 0)) }
            }
            guard !gone.isEmpty else { return }
            execute("BEGIN")
            let statements = [prepare("DELETE FROM files WHERE id = ?"), prepare("DELETE FROM content WHERE rowid = ?"),
                              prepare("DELETE FROM summaries WHERE rowid = ?")]
            for id in gone {
                for statement in statements {
                    sqlite3_reset(statement)
                    sqlite3_bind_int64(statement, 1, id)
                    sqlite3_step(statement)
                }
            }
            for statement in statements { sqlite3_finalize(statement) }
            execute("COMMIT")
        }
    }

    public func removeAll() {
        lock.withLock {
            execute("DELETE FROM files")
            execute("DELETE FROM content")
            execute("DELETE FROM summaries")
        }
    }

    // MARK: - ContentSearching

    public func search(terms: [String], limit: Int) -> [ContentHit] {
        // Each term as a quoted prefix, so punctuation in what the user typed can't be read as FTS syntax.
        let match = terms.map { $0.filter { $0.isLetter || $0.isNumber } }.filter { !$0.isEmpty }
            .map { "\"\($0)\"*" }.joined(separator: " ")
        guard !match.isEmpty else { return [] }
        return lock.withLock {
            var hits: [ContentHit] = []
            var found: Set<String> = []
            // What was written about a file first (it's the shorter, clearer thing to show), then its own text.
            for table in ["summaries", "content"] {
                let statement = prepare("""
                    SELECT files.path, snippet(\(table), 0, '', '', '…', 16)
                    FROM \(table) JOIN files ON files.id = \(table).rowid
                    WHERE \(table) MATCH ? ORDER BY rank LIMIT ?
                    """)
                Self.bind(statement, 1, match)
                sqlite3_bind_int(statement, 2, Int32(limit))
                while sqlite3_step(statement) == SQLITE_ROW {
                    let path = Self.text(statement, 0)
                    guard found.insert(path).inserted else { continue }
                    let snippet = Self.text(statement, 1).split(whereSeparator: \.isNewline).joined(separator: " ")
                    hits.append(ContentHit(path: path, snippet: snippet))
                }
                sqlite3_finalize(statement)
            }
            return hits
        }
    }

    // MARK: - IndexedTextReading

    public func indexedText(forPath path: String) -> String? {
        lock.withLock {
            let statement = prepare("SELECT content.body FROM content JOIN files ON files.id = content.rowid WHERE files.path = ?")
            defer { sqlite3_finalize(statement) }
            Self.bind(statement, 1, path)
            return sqlite3_step(statement) == SQLITE_ROW ? Self.text(statement, 0) : nil
        }
    }

    // MARK: - SQLite

    private func execute(_ sql: String) {
        sqlite3_exec(database, sql, nil, nil, nil)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        return statement
    }

    private func query(_ sql: String, row: (OpaquePointer?) -> Void) {
        let statement = prepare(sql)
        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
        sqlite3_finalize(statement)
    }

    private func userVersion() -> Int32 {
        var version: Int32 = 0
        query("PRAGMA user_version") { version = sqlite3_column_int($0, 0) }
        return version
    }

    private static func bind(_ statement: OpaquePointer?, _ index: Int32, _ text: String) {
        sqlite3_bind_text(statement, index, text, -1, transient)
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }
}
