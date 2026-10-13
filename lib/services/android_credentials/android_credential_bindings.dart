import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../base_shared_preferences_service.dart';
import '../credential_vault.dart';
import '../sensitive_prefs.dart';
import '../../models/seerr/seerr_session.dart';
import '../../utils/serial_future_queue.dart';
import 'android_credential_store.dart';

AndroidCredentialOwner connectionCredentialOwner(String id, String field, String label, Set<String> servers) =>
    AndroidCredentialOwner(jsonEncode(['connection', id, field]), label, serverIds: servers);
AndroidCredentialOwner profileCredentialOwner(
  String profileId,
  String connectionId, {
  Set<String> servers = const {},
}) => AndroidCredentialOwner(
  jsonEncode(['profile', profileId, connectionId]),
  'Profile $profileId · connection $connectionId',
  serverIds: servers,
);
AndroidCredentialOwner preferenceCredentialOwner(String key) {
  final base = profileScopedCredentialBaseKey(key);
  final name = switch (base) {
    'mal_session' => 'MyAnimeList',
    'anilist_session' => 'AniList',
    'simkl_session' => 'Simkl',
    'trakt_session' => 'Trakt',
    'mdblist_session' => 'MDBList',
    'seerr_session' => 'Seerr',
    _ => 'Saved service',
  };
  final profile = base != null && key.startsWith('user_') ? key.substring(5, key.length - base.length - 1) : null;
  return AndroidCredentialOwner(
    jsonEncode(['preference', key]),
    profile == null ? '$name sign-in' : '$name · profile $profile',
  );
}

class AndroidCredentialBindings {
  static Set<String> serverIds(String kind, Map<String, dynamic> config) => kind == 'plex'
      ? {
          for (final raw in (config['servers'] as List? ?? []))
            if (raw is Map && raw['clientIdentifier'] is String) raw['clientIdentifier'] as String,
        }
      : {if (config['serverMachineId'] is String) config['serverMachineId'] as String};

  static Future<({Map<String, dynamic> clear, Map<String, dynamic> stored, bool changed})> connection(
    String kind,
    String id,
    String label,
    Map<String, dynamic> source, {
    bool freshSignIn = false,
  }) async {
    final clear = Map<String, dynamic>.from(source);
    final stored = Map<String, dynamic>.from(source);
    final servers = serverIds(kind, source);
    var changed = false;
    Future<void> token(Map<String, dynamic> plain, Map<String, dynamic> saved, String field, String slot) async {
      final value = saved[field];
      if (value is! String || value.isEmpty) return;
      final owner = connectionCredentialOwner(
        id,
        slot,
        slot.startsWith('server/') ? '$label · ${saved['name'] ?? slot.substring(7)}' : '$label sign-in',
        servers,
      );
      if (freshSignIn) {
        saved[field] = await AndroidCredentialStore.save(owner, value);
      } else {
        final result = await AndroidCredentialStore.migrate(owner, value, CredentialVault.reveal);
        plain[field] = result.value ?? '';
        saved[field] = result.stored;
        changed = changed || result.changed;
      }
    }

    final field = kind == 'plex' ? 'accountToken' : 'accessToken';
    await token(clear, stored, field, field);
    if (kind == 'plex' && source['servers'] is List) {
      final clearServers = <dynamic>[];
      final storedServers = <dynamic>[];
      for (final raw in source['servers'] as List) {
        if (raw is! Map) {
          clearServers.add(raw);
          storedServers.add(raw);
          continue;
        }
        final plain = Map<String, dynamic>.from(raw);
        final saved = Map<String, dynamic>.from(raw);
        final serverId = saved['clientIdentifier'];
        if (serverId is String) await token(plain, saved, 'accessToken', 'server/$serverId');
        clearServers.add(plain);
        storedServers.add(saved);
      }
      clear['servers'] = clearServers;
      stored['servers'] = storedServers;
    }
    return (clear: clear, stored: stored, changed: changed);
  }

  static void preserveResetSources(String kind, String id, Map<String, dynamic> original, Map<String, dynamic> target) {
    void keep(Map<String, dynamic> old, Map<String, dynamic> next, String field, String slot) {
      final owner = connectionCredentialOwner(id, slot, '', {});
      if (AndroidCredentialStore.reauthenticationRequired.contains(owner.id) &&
          (next[field] == null || next[field] == '') &&
          old[field] is String) {
        next[field] = old[field];
      }
    }

    final field = kind == 'plex' ? 'accountToken' : 'accessToken';
    keep(original, target, field, field);
    final oldServers = original['servers'];
    final newServers = target['servers'];
    if (kind == 'plex' && oldServers is List && newServers is List) {
      for (final server in newServers.whereType<Map<String, dynamic>>()) {
        for (final old in oldServers.whereType<Map<String, dynamic>>()) {
          if (old['clientIdentifier'] == server['clientIdentifier']) {
            keep(old, server, 'accessToken', "server/${server['clientIdentifier']}");
          }
        }
      }
    }
  }

  static List<AndroidCredentialOwner> connectionOwners(
    String kind,
    String id,
    String label,
    Map<String, dynamic> config,
  ) {
    final servers = serverIds(kind, config);
    final field = kind == 'plex' ? 'accountToken' : 'accessToken';
    return [
      connectionCredentialOwner(id, field, '$label sign-in', servers),
      if (kind == 'plex')
        for (final raw in (config['servers'] as List? ?? []))
          if (raw is Map && raw['clientIdentifier'] is String)
            connectionCredentialOwner(id, 'server/${raw['clientIdentifier']}', '$label sign-in', servers),
    ];
  }

  static Future<void> removeConnection(String kind, String id, String label, Map<String, dynamic> config) async {
    for (final owner in connectionOwners(kind, id, label, config)) {
      await AndroidCredentialStore.remove(owner);
    }
  }

  static Future<void> removeProfileItems(AppDatabase db, {String? profileId, String? connectionId}) async {
    for (final row in await db.select(db.profileConnections).get()) {
      if (profileId != null && row.profileId != profileId) continue;
      if (connectionId != null && row.connectionId != connectionId) continue;
      await AndroidCredentialStore.remove(profileCredentialOwner(row.profileId, row.connectionId));
    }
  }

  static Future<void> checkAndMigrate(AppDatabase db) async {
    if (!AndroidCredentialStore.enabled) return;
    await db.runIdentityMutation(() async {
      final rows = await db.select(db.connections).get();
      final serversByConnection = <String, Set<String>>{};
      for (final row in rows) {
        final source = jsonDecode(row.configJson) as Map<String, dynamic>;
        serversByConnection[row.id] = serverIds(row.kind, source);
        final result = await connection(row.kind, row.id, row.displayName, source);
        if (result.changed) {
          await (db.update(db.connections)..where((t) => t.id.equals(row.id) & t.configJson.equals(row.configJson)))
              .write(ConnectionsCompanion(configJson: Value(jsonEncode(result.stored))));
        }
      }
      for (final row in await db.select(db.profileConnections).get()) {
        if (row.userToken.isEmpty) continue;
        final owner = profileCredentialOwner(
          row.profileId,
          row.connectionId,
          servers: serversByConnection[row.connectionId] ?? {},
        );
        final result = await AndroidCredentialStore.migrate(owner, row.userToken, CredentialVault.reveal);
        if (result.changed) {
          await (db.update(db.profileConnections)..where(
                (t) =>
                    t.profileId.equals(row.profileId) &
                    t.connectionId.equals(row.connectionId) &
                    t.userToken.equals(row.userToken),
              ))
              .write(ProfileConnectionsCompanion(userToken: Value(result.stored)));
        }
      }
    });
    final prefs = await BaseSharedPreferencesService.sharedCache();
    // Keep the old AES key and legacy bootstrap slots until their existing
    // consumers have committed the replacement; recovery must not destroy them.
    for (final key in prefs.keys.toList()) {
      if (profileScopedCredentialBaseKey(key) != null) await AndroidCredentialPreferences.load(key);
    }
  }
}

class AndroidCredentialPreferences {
  static final _queue = SerialFutureQueue();
  static Future<String?> load(String key) => _queue.run(() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final source = readTolerantString(prefs, key);
    if (source == null) return null;
    final result = await AndroidCredentialStore.migrate(preferenceCredentialOwner(key), source, (value) async {
      if (!isSeerrSessionPrefKey(key)) return value;
      final session = SeerrSession.decode(value);
      if (session.secret.isEmpty) return value;
      final secret = await CredentialVault.reveal(session.secret);
      if (secret == null) return null;
      return session.copyWith(secret: secret).encode();
    });
    if (result.changed) await prefs.setString(key, result.stored);
    return result.value;
  });
  static Future<void> save(String key, String value) => _queue.run(() async {
    final reference = await AndroidCredentialStore.save(preferenceCredentialOwner(key), value);
    await (await BaseSharedPreferencesService.sharedCache()).setString(key, reference);
  });
  static Future<void> clear(String key) => _queue.run(() async {
    await AndroidCredentialStore.remove(preferenceCredentialOwner(key));
    await (await BaseSharedPreferencesService.sharedCache()).remove(key);
  });
}
