import Foundation
import SQLite3

/// Local SQLite3 persistence layer for WarpNest preferences, per-game backend/profile overrides,
/// and operation history. Never stores gaming account credentials or tokens.
final class WarpPersistenceStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    let databaseURL: URL

    init(databaseURL: URL? = nil) {
        if let databaseURL {
            self.databaseURL = databaseURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("WarpNest", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.databaseURL = dir.appendingPathComponent("warpnest.sqlite")
        }
        openAndMigrate()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    private func openAndMigrate() {
        lock.lock()
        defer { lock.unlock() }

        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else { return }

        let schema = """
        CREATE TABLE IF NOT EXISTS preferences (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS game_profiles (
            app_id TEXT PRIMARY KEY,
            graphics_backend TEXT NOT NULL,
            cef_mode TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS operation_history (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            status TEXT NOT NULL,
            detail TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        """
        sqlite3_exec(db, schema, nil, nil, nil)
    }

    func getPreference(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }

        var stmt: OpaquePointer?
        let sql = "SELECT value FROM preferences WHERE key = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
            return String(cString: cStr)
        }
        return nil
    }

    func setPreference(_ key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }

        var stmt: OpaquePointer?
        let sql = "INSERT INTO preferences (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    func getGameBackendOverride(appId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }

        var stmt: OpaquePointer?
        let sql = "SELECT graphics_backend FROM game_profiles WHERE app_id = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (appId as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
            return String(cString: cStr)
        }
        return nil
    }

    func setGameBackendOverride(appId: String, backend: String, cefMode: String = "disable-gpu") {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }

        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO game_profiles (app_id, graphics_backend, cef_mode, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(app_id) DO UPDATE SET
            graphics_backend = excluded.graphics_backend,
            cef_mode = excluded.cef_mode,
            updated_at = excluded.updated_at;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let now = ISO8601DateFormatter().string(from: Date())
        sqlite3_bind_text(stmt, 1, (appId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (backend as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (cefMode as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (now as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    func recordOperation(id: String, title: String, status: String, detail: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }

        var stmt: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO operation_history (id, title, status, detail, created_at) VALUES (?, ?, ?, ?, ?);"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let now = ISO8601DateFormatter().string(from: Date())
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (status as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (detail as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (now as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }
}
