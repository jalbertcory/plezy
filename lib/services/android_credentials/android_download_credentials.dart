import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/services.dart';

import '../../utils/global_key_utils.dart';
import 'android_credential_store.dart';

const androidDownloadReferencePrefix = 'https://plezy-credential.invalid/';
bool isAndroidDownloadReference(Task task) => task.url.startsWith(androidDownloadReferencePrefix);
AndroidCredentialOwner androidDownloadOwner(Task task) {
  final key = parseGlobalKey(task.metaData);
  return AndroidCredentialOwner(
    jsonEncode(['download', task.taskId]),
    'Background download',
    serverIds: {if (key != null) key.serverId},
  );
}

Future<Task> protectAndroidDownload(Task task) async {
  final url = Uri.tryParse(task.url);
  if (url == null || !['http', 'https'].contains(url.scheme) || url.host.isEmpty) {
    throw StateError('Invalid download request');
  }
  final owner = androidDownloadOwner(task);
  await AndroidCredentialStore.save(owner, task.url);
  return task.copyWith(
    url: '$androidDownloadReferencePrefix${owner.id}',
    options: TaskOptions(onTaskStart: resolveAndroidDownload),
  );
}

/// The local Android plugin is registered by the worker's Flutter engine.
/// The patched Android worker retains only the original opaque task in its
/// context; this returned URL is used only to build the live HTTP request.
@pragma('vm:entry-point')
Future<Task?> resolveAndroidDownload(Task task) async {
  try {
    final owner = androidDownloadOwner(task);
    if (task.url != '$androidDownloadReferencePrefix${owner.id}') throw StateError('Invalid download reference');
    final value = await AndroidCredentialStore.revealReference(AndroidCredentialStore.reference(owner), owner: owner);
    final url = value == null ? null : Uri.tryParse(value);
    if (url == null || !['http', 'https'].contains(url.scheme) || url.host.isEmpty) {
      throw StateError('Missing credential');
    }
    return task.copyWith(url: value);
  } catch (_) {
    throw PlatformException(code: 'credential_unavailable', message: 'Download credential unavailable');
  }
}

Future<void> removeAndroidDownloadCredential(Task task) => AndroidCredentialStore.remove(androidDownloadOwner(task));
