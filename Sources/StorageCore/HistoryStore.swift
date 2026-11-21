import Foundation
import SQLite3

/// Uma amostra de ocupação de um volume.
public struct StorageSample: Equatable, Sendable {
    public var date: Date
    public var totalBytes: Int64
    public var freeBytes: Int64
    public var purgeableBytes: Int64

    public init(date: Date, totalBytes: Int64, freeBytes: Int64, purgeableBytes: Int64) {
        self.date = date
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.purgeableBytes = purgeableBytes
    }

    public init(volume: VolumeInfo, date: Date) {
        self.init(date: date, totalBytes: volume.totalBytes,
                  freeBytes: volume.freeBytes, purgeableBytes: volume.purgeableBytes)
    }

    public var usedBytes: Int64 { max(0, totalBytes - freeBytes) }
}

/// Histórico de ocupação em SQLite (sem dependências externas).
///
/// Retenção, aplicada por `compact(now:)`:
/// - últimas 48 h: amostras originais (a cada 5 min);
/// - de 48 h a 60 dias: média por hora;
/// - mais de 60 dias: média por dia.
public final class HistoryStore: @unchecked Sendable {
    public static let rawRetention: TimeInterval = 48 * 3600
    public static let hourlyRetention: TimeInterval = 60 * 86_400

    private var db: OpaquePointer?
    private let lock = NSLock()

    public enum StoreError: Error, CustomStringConvertible {
        case sqlite(String)
        public var description: String {
            switch self { case .sqlite(let message): "SQLite: \(message)" }
        }
    }

    /// Local padrão: ~/Library/Application Support/DiskNotch/history.sqlite
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DiskNotch/history.sqlite")
    }

    /// Caminho no home real do usuário, mesmo dentro de uma sandbox (usado pelo widget,
    /// cujo `applicationSupportDirectory` aponta para o próprio contêiner).
    public static var sharedURL: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/DiskNotch/history.sqlite")
    }

    /// - Parameter readOnly: abre sem criar o arquivo nem as tabelas (para o widget).
    public init(url: URL = HistoryStore.defaultURL, readOnly: Bool = false) throws {
        if readOnly {
            guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                throw StoreError.sqlite("não abriu \(url.path) para leitura")
            }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw StoreError.sqlite("não abriu \(url.path)")
        }
        try exec("""
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS samples (
                volume_id TEXT NOT NULL,
                ts INTEGER NOT NULL,
                total INTEGER NOT NULL,
                free INTEGER NOT NULL,
                purgeable INTEGER NOT NULL,
                PRIMARY KEY (volume_id, ts)
            ) WITHOUT ROWID;
            """)
    }

    deinit { sqlite3_close(db) }

    // MARK: Escrita

    public func insert(_ sample: StorageSample, volumeID: String) throws {
        try locked {
            let sql = "INSERT OR REPLACE INTO samples VALUES (?, ?, ?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, volumeID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, Int64(sample.date.timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 3, sample.totalBytes)
            sqlite3_bind_int64(stmt, 4, sample.freeBytes)
            sqlite3_bind_int64(stmt, 5, sample.purgeableBytes)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw lastError() }
        }
    }

    /// Junta amostras antigas em médias por hora e por dia.
    public func compact(now: Date = .now) throws {
        let t = Int64(now.timeIntervalSince1970)
        try locked {
            try execUnlocked("BEGIN")
            do {
                try aggregate(bucket: 3600, before: t - Int64(Self.rawRetention))
                try aggregate(bucket: 86_400, before: t - Int64(Self.hourlyRetention))
                try execUnlocked("COMMIT")
            } catch {
                try? execUnlocked("ROLLBACK")
                throw error
            }
        }
    }

    /// Troca todas as amostras de cada intervalo (anteriores a `before`) por uma só, com a média.
    private func aggregate(bucket: Int64, before: Int64) throws {
        try execUnlocked("""
            DROP TABLE IF EXISTS temp.agg;
            CREATE TEMP TABLE agg AS
                SELECT volume_id, (ts / \(bucket)) * \(bucket) AS b,
                       CAST(AVG(total) AS INTEGER) AS total,
                       CAST(AVG(free) AS INTEGER) AS free,
                       CAST(AVG(purgeable) AS INTEGER) AS purgeable
                FROM samples
                WHERE ts < \(before)
                GROUP BY volume_id, b
                HAVING COUNT(*) > 1 OR MIN(ts % \(bucket)) != 0;
            DELETE FROM samples
                WHERE ts < \(before)
                  AND (volume_id, (ts / \(bucket)) * \(bucket)) IN (SELECT volume_id, b FROM agg);
            INSERT INTO samples SELECT volume_id, b, total, free, purgeable FROM agg;
            DROP TABLE temp.agg;
            """)
    }

    // MARK: Leitura

    public func samples(volumeID: String, since: Date, until: Date = .distantFuture) throws -> [StorageSample] {
        try locked {
            let sql = "SELECT ts, total, free, purgeable FROM samples WHERE volume_id = ? AND ts >= ? AND ts <= ? ORDER BY ts"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, volumeID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, Int64(max(0, since.timeIntervalSince1970)))
            sqlite3_bind_int64(stmt, 3, Int64(min(until.timeIntervalSince1970, 4_000_000_000)))
            var result: [StorageSample] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(StorageSample(
                    date: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 0))),
                    totalBytes: sqlite3_column_int64(stmt, 1),
                    freeBytes: sqlite3_column_int64(stmt, 2),
                    purgeableBytes: sqlite3_column_int64(stmt, 3)))
            }
            return result
        }
    }

    public func count() throws -> Int {
        try locked {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM samples", -1, &stmt, nil) == SQLITE_OK else { throw lastError() }
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
        }
    }

    // MARK: Auxiliares

    private func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func exec(_ sql: String) throws { try locked { try execUnlocked(sql) } }

    private func execUnlocked(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? "erro desconhecido"
            sqlite3_free(message)
            throw StoreError.sqlite(text)
        }
    }

    private func lastError() -> StoreError {
        StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
    }
}

/// SQLITE_TRANSIENT não é importado pelo Swift.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
