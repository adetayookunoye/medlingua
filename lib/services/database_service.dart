import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/triage_encounter.dart';

/// Persistent storage for triage encounters using SQLite.
///
/// Data survives app restarts. Falls back to in-memory storage only if
/// the database fails to open (e.g., unit-test environments).
class DatabaseService {
  static Database? _db;
  static const String _tableName = 'encounters';

  /// Open (or create) the SQLite database.
  Future<Database> get database async {
    if (_db != null) return _db!;
    try {
      final dbPath = await getDatabasesPath();
      _db = await openDatabase(
        p.join(dbPath, 'medlingua.db'),
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_tableName (
              id TEXT PRIMARY KEY,
              timestamp TEXT NOT NULL,
              patientName TEXT NOT NULL,
              patientAge INTEGER,
              patientGender TEXT,
              symptoms TEXT NOT NULL,
              imagePath TEXT,
              inputLanguage TEXT NOT NULL,
              severity TEXT NOT NULL,
              diagnosis TEXT NOT NULL,
              recommendation TEXT NOT NULL,
              referralNote TEXT,
              confidenceScore REAL NOT NULL,
              isOffline INTEGER NOT NULL
            )
          ''');
        },
      );
      debugPrint('DatabaseService: Opened SQLite database at $dbPath');
      return _db!;
    } catch (e) {
      debugPrint('DatabaseService: Failed to open database: $e');
      rethrow;
    }
  }

  /// Save a triage encounter (insert or replace).
  Future<void> saveEncounter(TriageEncounter encounter) async {
    try {
      final db = await database;
      await db.insert(
        _tableName,
        encounter.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } on DatabaseException catch (e) {
      debugPrint('DatabaseService.saveEncounter: $e');
      throw DatabaseServiceException('Failed to save encounter', cause: e);
    } catch (e, stackTrace) {
      debugPrint('DatabaseService.saveEncounter unexpected: $e\n$stackTrace');
      throw DatabaseServiceException('Unexpected error saving encounter', cause: e);
    }
  }

  /// Get all encounters, most recent first.
  Future<List<TriageEncounter>> getAllEncounters() async {
    try {
      final db = await database;
      final rows = await db.query(
        _tableName,
        orderBy: 'timestamp DESC',
      );
      return rows.map((row) => TriageEncounter.fromMap(row)).toList();
    } on DatabaseException catch (e) {
      debugPrint('DatabaseService.getAllEncounters: $e');
      return [];
    } catch (e, stackTrace) {
      debugPrint('DatabaseService.getAllEncounters unexpected: $e\n$stackTrace');
      return [];
    }
  }

  /// Get encounter by ID.
  Future<TriageEncounter?> getEncounter(String id) async {
    try {
      final db = await database;
      final rows = await db.query(
        _tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return TriageEncounter.fromMap(rows.first);
    } on DatabaseException catch (e) {
      debugPrint('DatabaseService.getEncounter: $e');
      return null;
    } catch (e, stackTrace) {
      debugPrint('DatabaseService.getEncounter unexpected: $e\n$stackTrace');
      return null;
    }
  }

  /// Get encounters by severity.
  Future<List<TriageEncounter>> getEncountersBySeverity(
      TriageSeverity severity) async {
    try {
      final db = await database;
      final rows = await db.query(
        _tableName,
        where: 'severity = ?',
        whereArgs: [severity.name],
        orderBy: 'timestamp DESC',
      );
      return rows.map((row) => TriageEncounter.fromMap(row)).toList();
    } on DatabaseException catch (e) {
      debugPrint('DatabaseService.getEncountersBySeverity: $e');
      return [];
    } catch (e, stackTrace) {
      debugPrint('DatabaseService.getEncountersBySeverity unexpected: $e\n$stackTrace');
      return [];
    }
  }

  /// Get encounters within a date range.
  Future<List<TriageEncounter>> getEncountersByDateRange(
      DateTime start, DateTime end) async {
    try {
      final db = await database;
      final rows = await db.query(
        _tableName,
        where: 'timestamp >= ? AND timestamp <= ?',
        whereArgs: [start.toIso8601String(), end.toIso8601String()],
        orderBy: 'timestamp DESC',
      );
      return rows.map((row) => TriageEncounter.fromMap(row)).toList();
    } on DatabaseException catch (e) {
      debugPrint('DatabaseService.getEncountersByDateRange: $e');
      return [];
    } catch (e, stackTrace) {
      debugPrint('DatabaseService.getEncountersByDateRange unexpected: $e\n$stackTrace');
      return [];
    }
  }

  /// Get encounter count for analytics.
  Future<Map<String, int>> getEncounterStats() async {
    try {
      final db = await database;
      final countResult = await db.rawQuery(
        'SELECT severity, COUNT(*) as count FROM $_tableName GROUP BY severity',
      );

      final stats = <String, int>{
        'total': 0,
        'emergency': 0,
        'urgent': 0,
        'standard': 0,
        'routine': 0,
      };

      for (final row in countResult) {
        final severity = row['severity'] as String;
        final count = row['count'] as int;
        stats[severity] = count;
        stats['total'] = (stats['total'] ?? 0) + count;
      }

      return stats;
    } on DatabaseException catch (e) {
      debugPrint('DatabaseService.getEncounterStats: $e');
      return {'total': 0, 'emergency': 0, 'urgent': 0, 'standard': 0, 'routine': 0};
    } catch (e, stackTrace) {
      debugPrint('DatabaseService.getEncounterStats unexpected: $e\n$stackTrace');
      return {'total': 0, 'emergency': 0, 'urgent': 0, 'standard': 0, 'routine': 0};
    }
  }

  /// Delete an encounter.
  Future<void> deleteEncounter(String id) async {
    try {
      final db = await database;
      await db.delete(
        _tableName,
        where: 'id = ?',
        whereArgs: [id],
      );
    } on DatabaseException catch (e) {
      debugPrint('DatabaseService.deleteEncounter: $e');
      throw DatabaseServiceException('Failed to delete encounter', cause: e);
    } catch (e, stackTrace) {
      debugPrint('DatabaseService.deleteEncounter unexpected: $e\n$stackTrace');
      throw DatabaseServiceException('Unexpected error deleting encounter', cause: e);
    }
  }

  /// Close the database connection.
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}

/// Exception thrown by DatabaseService operations.
class DatabaseServiceException implements Exception {
  final String message;
  final Object? cause;
  const DatabaseServiceException(this.message, {this.cause});

  @override
  String toString() => 'DatabaseServiceException: $message${cause != null ? ' ($cause)' : ''}';
}
