import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';

import '../../database/app_database.dart';
import '../../profiles/profile.dart';
import '../../media/ids.dart';
import '../../utils/active_client_scope.dart';
import '../../utils/global_key_utils.dart';
import 'android_download_credentials.dart';
import 'android_credential_store.dart';

enum AndroidTransferOwnership { selected, unrelated, ambiguous }

/// Public server identity alone cannot distinguish two accounts on one server.
/// Missing or legacy provenance blocks reset instead of widening its scope.
AndroidTransferOwnership androidTransferOwnership(
  AndroidCredentialOwner owner, {
  required String taskId,
  required String serverId,
  required String? clientScopeId,
}) {
  final parts = jsonDecode(owner.scope) as List;
  if (parts.first == 'download') {
    return parts[1] == taskId ? AndroidTransferOwnership.selected : AndroidTransferOwnership.unrelated;
  }
  if (parts.first == 'preference') return AndroidTransferOwnership.unrelated;
  if (owner.serverIds.isNotEmpty && !owner.serverIds.contains(serverId)) return AndroidTransferOwnership.unrelated;
  final connectionId = parts.first == 'connection' ? parts[1] as String : parts[2] as String;
  if (parts.first == 'connection' && (parts[2] as String).startsWith('server/') && parts[2] != 'server/$serverId') {
    return AndroidTransferOwnership.unrelated;
  }
  final plexScope = PlexProfileScopeId.tryParse(clientScopeId ?? '');
  if (plexScope != null) {
    final home = parsePlexHomeProfileId(plexScope.profileId);
    if (home == null) return AndroidTransferOwnership.ambiguous;
    if (home.accountConnectionId != connectionId) return AndroidTransferOwnership.unrelated;
    if (parts.first == 'profile' && plexScope.profileId != parts[1]) return AndroidTransferOwnership.unrelated;
    return AndroidTransferOwnership.selected;
  }
  if (clientScopeId != null && isJellyfinUserScopeId(serverId: ServerId(serverId), cacheServerId: clientScopeId)) {
    return clientScopeId == connectionId ? AndroidTransferOwnership.selected : AndroidTransferOwnership.unrelated;
  }
  return AndroidTransferOwnership.ambiguous;
}

/// Called after providers have detached and only after explicit confirmation.
/// Inspect nonsecret provenance before any cancellation or deletion.
Future<void> stopAndroidCredentialTransfers(AndroidCredentialOwner owner) async {
  if ((jsonDecode(owner.scope) as List).first == 'preference') return;
  final downloader = FileDownloader();
  final tasks = <String, Task>{
    for (final record in await downloader.database.allRecords(group: 'video_downloads'))
      if (![TaskStatus.complete, TaskStatus.canceled, TaskStatus.notFound].contains(record.status))
        record.taskId: record.task,
    for (final task in await downloader.allTasks(group: 'video_downloads')) task.taskId: task,
  };
  if (tasks.isEmpty) return;
  final database = (await AppDatabase.open(isTvos: false)).database;
  final affected = <Task>[];
  try {
    final rows = {for (final row in await database.select(database.downloadedMedia).get()) row.globalKey: row};
    for (final task in tasks.values) {
      final key = parseGlobalKey(task.metaData);
      if (key == null) throw StateError('Download ownership unavailable');
      final row = rows[task.metaData];
      final ownership = androidTransferOwnership(
        owner,
        taskId: task.taskId,
        serverId: key.serverId,
        clientScopeId: row?.bgTaskId == task.taskId ? row?.clientScopeId : null,
      );
      if (ownership == AndroidTransferOwnership.ambiguous) throw StateError('Download ownership unavailable');
      if (ownership == AndroidTransferOwnership.selected) affected.add(task);
    }
  } finally {
    await database.close();
  }
  if (affected.isEmpty) return;
  if (!await downloader.cancelTasksWithIds(affected.map((task) => task.taskId))) {
    throw StateError('Could not stop affected downloads');
  }
  for (final task in affected) {
    // For a failed per-task key, leave its deletion to the revision-checked
    // reset below. Other derived request keys belong to this selected sign-in.
    if (androidDownloadOwner(task).id != owner.id) await removeAndroidDownloadCredential(task);
    await downloader.database.deleteRecordWithId(task.taskId);
  }
}

/// Lives above the failure widget so rebuilding that widget cannot reset its
/// retry budget. No timers, automatic retries, or automatic destructive action.
class AndroidCredentialRetryBudget {
  static const maximum = 2;
  final Map<String, int> _attempts = {};
  int remaining(AndroidCredentialFailure failure) => maximum - (_attempts[failure.owner.id] ?? 0);
  bool take(AndroidCredentialFailure failure) {
    if (remaining(failure) <= 0) return false;
    _attempts.update(failure.owner.id, (value) => value + 1, ifAbsent: () => 1);
    return true;
  }
}
