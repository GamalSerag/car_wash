import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/local_sale.dart';
import '../models/offline_sync_batch.dart';

class OfflineStore {
  OfflineStore(this.db);
  final Database db;
  static const uuid = Uuid();

  static Future<OfflineStore> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final database = await f.openDatabase(
      path ?? p.join(await f.getDatabasesPath(), 'maghsala_offline_v1.db'),
      options: OpenDatabaseOptions(
        version: 1,
        // Each Flutter engine owns its handle; a worker must not close the UI's.
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA busy_timeout = 5000');
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE cache (key TEXT PRIMARY KEY, value TEXT NOT NULL, at INTEGER NOT NULL)',
          );
          await db.execute('''CREATE TABLE queue (
          id TEXT PRIMARY KEY, user_id TEXT NOT NULL, company_id TEXT NOT NULL,
          payload TEXT NOT NULL, state TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 0,
          batch_id TEXT, server_id INTEGER, error TEXT, ack_at INTEGER)''');
          await db.execute(
            'CREATE INDEX queue_owner ON queue(user_id, company_id)',
          );
          await db.execute(
            '''CREATE TABLE activity (id TEXT PRIMARY KEY, sale_id TEXT NOT NULL,
          user_id TEXT NOT NULL, company_id TEXT NOT NULL, kind TEXT NOT NULL,
          before_payload TEXT, after_payload TEXT, occurred_at TEXT NOT NULL, batch_id TEXT)''',
          );
          await db.execute(
            '''CREATE TABLE batches (id TEXT PRIMARY KEY, user_id TEXT NOT NULL,
          company_id TEXT NOT NULL, manifest TEXT NOT NULL, completed INTEGER NOT NULL DEFAULT 0)''',
          );
          await db.execute(
            'CREATE TABLE leases (scope TEXT PRIMARY KEY, owner TEXT NOT NULL, expires INTEGER NOT NULL, fence INTEGER NOT NULL)',
          );
        },
      ),
    );
    return OfflineStore(database);
  }

  Future<Map<String, dynamic>?> cache(String key) async {
    final rows = await db.query('cache', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return {
      'value': jsonDecode(rows.single['value'] as String),
      'at': rows.single['at'],
    };
  }

  Future<void> put(String key, Object? value) async => db.insert('cache', {
    'key': key,
    'value': jsonEncode(value),
    'at': DateTime.now().millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> remove(String key) async {
    await db.delete('cache', where: 'key = ?', whereArgs: [key]);
  }

  Future<LocalSale> enqueue(
    String user,
    String company,
    Map<String, dynamic> payload, {
    bool online = false,
  }) async {
    final id = uuid.v4();
    await db.transaction((tx) async {
      await tx.insert('queue', {
        'id': id,
        'user_id': user,
        'company_id': company,
        'payload': jsonEncode(payload),
        'state': online ? 'uncertain' : 'pending',
      });
      await _action(tx, id, user, company, 'create', null, payload);
    });
    return (await rows(user, company)).firstWhere((e) => e.localId == id);
  }

  Future<void> _action(
    DatabaseExecutor tx,
    String id,
    String user,
    String company,
    String kind,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  ) async {
    await tx.insert('activity', {
      'id': uuid.v4(),
      'sale_id': id,
      'user_id': user,
      'company_id': company,
      'kind': kind,
      'before_payload': before == null ? null : jsonEncode(before),
      'after_payload': after == null ? null : jsonEncode(after),
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<LocalSale>> rows(String user, String company) async {
    final data = await db.query(
      'queue',
      where: 'user_id = ? AND company_id = ?',
      whereArgs: [user, company],
    );
    return data
        .map(
          (r) => LocalSale(
            localId: r['id'] as String,
            userId: user,
            companyId: company,
            payload: Map<String, dynamic>.from(
              jsonDecode(r['payload'] as String) as Map,
            ),
            state: r['state'] as String,
            revision: r['revision'] as int,
            batchId: r['batch_id'] as String?,
            serverId: r['server_id'] as int?,
            error: r['error'] as String?,
            ackAt: r['ack_at'] as int?,
          ),
        )
        .toList();
  }

  Future<void> edit(
    LocalSale sale,
    Map<String, dynamic> payload, {
    bool cancel = false,
  }) async {
    await db.transaction((tx) async {
      final count = await tx.update(
        'queue',
        {
          'payload': jsonEncode(payload),
          'state': cancel ? 'cancelled' : 'pending',
          'revision': sale.revision + 1,
        },
        where:
            'id = ? AND user_id = ? AND company_id = ? AND revision = ? AND state = ? AND batch_id IS NULL',
        whereArgs: [
          sale.localId,
          sale.userId,
          sale.companyId,
          sale.revision,
          'pending',
        ],
      );
      if (count != 1)
        throw StateError('تم تغيير حالة العملية. حدّث البيانات أولًا');
      await _action(
        tx,
        sale.localId,
        sale.userId,
        sale.companyId,
        cancel ? 'cancel' : 'edit',
        sale.payload,
        cancel ? null : payload,
      );
    });
  }

  Future<void> mark(
    String id,
    String state, {
    int? serverId,
    String? error,
  }) async {
    await db.update(
      'queue',
      {'state': state, 'server_id': serverId, 'error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> reconcileOnline(String id, int serverId) async {
    await db.transaction((tx) async {
      await tx.update(
        'queue',
        {
          'state': 'synced',
          'server_id': serverId,
          'error': null,
          'ack_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await tx.delete(
        'activity',
        where: 'sale_id = ? AND batch_id IS NULL',
        whereArgs: [id],
      );
    });
  }

  Future<bool> hasUnsentActivity(String user, String company) async {
    final rows = await db.rawQuery(
      '''SELECT 1 FROM activity a LEFT JOIN batches b ON b.id=a.batch_id
      WHERE a.user_id=? AND a.company_id=? AND (a.batch_id IS NULL OR b.completed=0) LIMIT 1''',
      [user, company],
    );
    return rows.isNotEmpty;
  }

  Future<void> retainUnattemptedAsOffline(String user) async {
    await db.rawUpdate(
      """UPDATE queue SET state='pending' WHERE user_id=? AND state='uncertain'
      AND batch_id IS NULL AND NOT EXISTS(SELECT 1 FROM cache WHERE cache.key='attempt:' || queue.id)""",
      [user],
    );
  }

  Future<OfflineSyncBatch?> freeze(String user, String company) async {
    return db.transaction((tx) async {
      final existing = await tx.query(
        'batches',
        where: 'user_id = ? AND company_id = ? AND completed = 0',
        whereArgs: [user, company],
        orderBy: 'rowid',
        limit: 1,
      );
      if (existing.isNotEmpty) return _batch(existing.single);
      final pending = await tx.query(
        'queue',
        where:
            "user_id = ? AND company_id = ? AND batch_id IS NULL AND state IN ('pending','cancelled')",
        whereArgs: [user, company],
        orderBy: 'id',
      );
      if (pending.isEmpty) return null;
      final id = uuid.v4();
      final items = <Map<String, dynamic>>[];
      for (final row in pending) {
        items.add({
          'id': row['id'],
          'payload': jsonDecode(row['payload'] as String),
          'cancelled': row['state'] == 'cancelled',
        });
        await tx.update(
          'queue',
          {'batch_id': id, if (row['state'] != 'cancelled') 'state': 'frozen'},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      final events = await tx.query(
        'activity',
        where: 'user_id = ? AND company_id = ? AND batch_id IS NULL',
        whereArgs: [user, company],
        orderBy: 'rowid',
      );
      final actions = <Map<String, dynamic>>[];
      for (final event in events) {
        actions.add({
          'id': event['id'],
          'sale_id': event['sale_id'],
          'kind': event['kind'],
          'sequence_no': actions.length + 1,
          'occurred_at': event['occurred_at'],
          'before': event['before_payload'] == null
              ? null
              : jsonDecode(event['before_payload'] as String),
          'after': event['after_payload'] == null
              ? null
              : jsonDecode(event['after_payload'] as String),
        });
        await tx.update(
          'activity',
          {'batch_id': id},
          where: 'id = ?',
          whereArgs: [event['id']],
        );
      }
      final row = {
        'id': id,
        'user_id': user,
        'company_id': company,
        'manifest': jsonEncode({'items': items, 'actions': actions}),
      };
      await tx.insert('batches', row);
      return _batch(row);
    });
  }

  OfflineSyncBatch _batch(Map<String, Object?> row) {
    final data = jsonDecode(row['manifest'] as String) as Map;
    return OfflineSyncBatch(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      companyId: row['company_id'] as String,
      items: (data['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      actions: (data['actions'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  Future<void> applyResults(
    String batch,
    List<dynamic> results,
    bool completed,
  ) async {
    await db.transaction((tx) async {
      for (final raw in results) {
        final r = raw as Map;
        await tx.update(
          'queue',
          {
            'state': switch (r['state']) {
              'accepted' => 'synced',
              'rejected' => 'failed',
              'cancelled' => 'cancelled',
              _ => 'frozen',
            },
            'server_id': r['sale_id'],
            'error': r['error_code'],
            'ack_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ? AND batch_id = ?',
          whereArgs: [r['id'], batch],
        );
      }
      if (completed)
        await tx.update(
          'batches',
          {'completed': 1},
          where: 'id = ?',
          whereArgs: [batch],
        );
    });
  }

  Future<int?> acquire(
    String scope,
    String owner, {
    Duration ttl = const Duration(minutes: 2),
  }) async {
    return db.transaction((tx) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rows = await tx.query(
        'leases',
        where: 'scope = ?',
        whereArgs: [scope],
      );
      if (rows.isNotEmpty && (rows.single['expires'] as int) > now) return null;
      final fence = rows.isEmpty ? 1 : (rows.single['fence'] as int) + 1;
      await tx.insert('leases', {
        'scope': scope,
        'owner': owner,
        'expires': now + ttl.inMilliseconds,
        'fence': fence,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return fence;
    });
  }

  Future<bool> renew(String scope, String owner, int fence) async =>
      await db.update(
        'leases',
        {
          'expires': DateTime.now()
              .add(const Duration(minutes: 2))
              .millisecondsSinceEpoch,
        },
        where: 'scope = ? AND owner = ? AND fence = ? AND expires > ?',
        whereArgs: [scope, owner, fence, DateTime.now().millisecondsSinceEpoch],
      ) ==
      1;

  Future<void> release(String scope, String owner, int fence) async {
    await db.update(
      'leases',
      {'expires': 0},
      where: 'scope = ? AND owner = ? AND fence = ?',
      whereArgs: [scope, owner, fence],
    );
  }
}
