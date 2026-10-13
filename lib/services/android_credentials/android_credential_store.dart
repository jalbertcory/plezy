import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../utils/serial_future_queue.dart';

enum AndroidCredentialProblem { unavailable, permanent, resetPending, stale }

class AndroidCredentialOwner {
  const AndroidCredentialOwner(this.scope, this.label, {this.serverIds = const {}});
  final String scope;
  final String label;
  final Set<String> serverIds;
  String get id => sha256.convert(utf8.encode(scope)).toString();
}

class AndroidCredentialFailure implements Exception {
  const AndroidCredentialFailure(this.owner, this.problem, this.revision);
  final AndroidCredentialOwner owner;
  final AndroidCredentialProblem problem;
  final String revision;
  bool get canReset =>
      problem == AndroidCredentialProblem.permanent || problem == AndroidCredentialProblem.resetPending;
  @override
  String toString() => 'Android credential storage unavailable';
}

class AndroidCredentialItem {
  const AndroidCredentialItem(this.state, this.revision, [this.value]);
  final String state;
  final String revision;
  final String? value;
}

abstract interface class AndroidCredentialBackend {
  Future<AndroidCredentialItem> read(String id);
  Future<AndroidCredentialItem> write(String id, String value);
  Future<AndroidCredentialItem> reset(String id, String revision);
  Future<void> delete(String id);
  Future<List<String>> listOwnedIds();
}

class AndroidCredentialChannel implements AndroidCredentialBackend {
  static const _channel = MethodChannel('com.plezy/android_credentials');
  Future<AndroidCredentialItem> _call(String operation, String id, [Map<String, String> args = const {}]) async {
    final raw = await _channel
        .invokeMapMethod<String, dynamic>(operation, {'id': id, ...args})
        .timeout(const Duration(seconds: 15));
    if (raw == null) throw PlatformException(code: 'unavailable');
    return AndroidCredentialItem(raw['state'] as String, raw['revision'] as String, raw['value'] as String?);
  }

  @override
  Future<AndroidCredentialItem> read(String id) => _call('read', id);
  @override
  Future<AndroidCredentialItem> write(String id, String value) => _call('write', id, {'value': value});
  @override
  Future<AndroidCredentialItem> reset(String id, String revision) => _call('reset', id, {'revision': revision});
  @override
  Future<List<String>> listOwnedIds() async {
    final ids = await _channel.invokeListMethod<String>('listOwnedIds').timeout(const Duration(seconds: 15));
    if (ids == null) throw PlatformException(code: 'unavailable');
    return ids;
  }

  @override
  Future<void> delete(String id) =>
      _channel.invokeMethod<void>('delete', {'id': id}).timeout(const Duration(seconds: 15));
}

/// Android-only. Other platforms never invoke this backend or change formats.
class AndroidCredentialStore {
  static const prefix = 'android-secure:v1:';
  static AndroidCredentialBackend _backend = AndroidCredentialChannel();
  static bool? _enabledForTesting;
  static final _queue = SerialFutureQueue();
  static final failureEvents = ValueNotifier<AndroidCredentialFailure?>(null);
  static final Map<String, AndroidCredentialOwner> _owners = {};
  static final Set<String> reauthenticationRequired = {};
  static bool get enabled => _enabledForTesting ?? (!kIsWeb && io.Platform.isAndroid);
  static bool get requiresAccountSignIn => reauthenticationRequired.any((id) {
    final owner = _owners[id];
    if (owner == null) return false;
    final parts = jsonDecode(owner.scope) as List;
    return parts.first == 'connection' || parts.first == 'profile';
  });
  static bool isReference(String value) => value.startsWith(prefix);
  static String reference(AndroidCredentialOwner owner) => '$prefix${owner.id}';

  @visibleForTesting
  static void configureForTesting(AndroidCredentialBackend? backend, {bool? enabled}) {
    _queue.reset();
    _backend = backend ?? AndroidCredentialChannel();
    _enabledForTesting = enabled;
    _owners.clear();
    reauthenticationRequired.clear();
    failureEvents.value = null;
  }

  static AndroidCredentialFailure _report(AndroidCredentialFailure failure) {
    if (enabled) failureEvents.value = failure;
    return failure;
  }

  static Future<T> _invoke<T>(AndroidCredentialOwner owner, Future<T> Function() action) async {
    final previous = _owners[owner.id];
    if (owner.serverIds.isEmpty && previous != null && previous.serverIds.isNotEmpty) owner = previous;
    _owners[owner.id] = owner;
    try {
      return await action();
    } on AndroidCredentialFailure catch (failure) {
      throw _report(
        AndroidCredentialFailure(_owners[failure.owner.id] ?? failure.owner, failure.problem, failure.revision),
      );
    } on PlatformException catch (error) {
      final problem = switch (error.code) {
        'permanent' => AndroidCredentialProblem.permanent,
        'reset_pending' => AndroidCredentialProblem.resetPending,
        'stale' => AndroidCredentialProblem.stale,
        _ => AndroidCredentialProblem.unavailable,
      };
      final details = error.details;
      final revision = details is Map && details['revision'] is String ? details['revision'] as String : 'unknown';
      throw _report(AndroidCredentialFailure(owner, problem, revision));
    } catch (_) {
      throw _report(AndroidCredentialFailure(owner, AndroidCredentialProblem.unavailable, 'unknown'));
    }
  }

  static Future<String?> revealReference(String value, {AndroidCredentialOwner? owner}) async {
    final id = value.substring(prefix.length);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id) || (owner != null && id != owner.id)) {
      throw const FormatException('Invalid Android credential reference');
    }
    final knownOwner = owner ?? _owners[id];
    if (knownOwner == null) throw StateError('Credential owner is not registered');
    return _queue.run(
      () => _invoke(knownOwner, () async {
        final item = await _backend.read(id);
        if (item.state == 'reauth') {
          reauthenticationRequired.add(id);
          return null;
        }
        if (item.state != 'ready' || item.value == null) {
          throw AndroidCredentialFailure(knownOwner, AndroidCredentialProblem.permanent, item.revision);
        }
        return item.value;
      }),
    );
  }

  /// Migration never overwrites its caller's source. The caller commits the
  /// returned reference only after this method verifies the secure value.
  static Future<({String? value, String stored, bool changed})> migrate(
    AndroidCredentialOwner owner,
    String source,
    Future<String?> Function(String) decodeLegacy,
  ) async {
    if (source.isEmpty) return (value: source, stored: source, changed: false);
    if (isReference(source)) {
      return (value: await revealReference(source, owner: owner), stored: source, changed: false);
    }
    return _queue.run(
      () => _invoke(owner, () async {
        final item = await _backend.read(owner.id);
        if (item.state == 'reauth') {
          reauthenticationRequired.add(owner.id);
          // Preserve a legacy source after interrupted migration. Never silently
          // resurrect its old sign-in after the user elected to reset it.
          return (value: null, stored: source, changed: false);
        }
        final clear = item.state == 'ready' ? item.value : await decodeLegacy(source);
        if (clear == null) throw AndroidCredentialFailure(owner, AndroidCredentialProblem.permanent, item.revision);
        if (item.state != 'ready') await _verifiedWrite(owner, clear);
        return (value: clear, stored: reference(owner), changed: true);
      }),
    );
  }

  static Future<void> _verifiedWrite(AndroidCredentialOwner owner, String value) async {
    final written = await _backend.write(owner.id, value);
    final checked = await _backend.read(owner.id);
    if (written.state != 'ready' || checked.state != 'ready' || checked.value != value) {
      throw AndroidCredentialFailure(owner, AndroidCredentialProblem.unavailable, checked.revision);
    }
  }

  /// Called only for an explicit fresh sign-in/token update, not migration.
  static Future<String> save(AndroidCredentialOwner owner, String value) => _queue.run(
    () => _invoke(owner, () async {
      await _verifiedWrite(owner, value);
      reauthenticationRequired.remove(owner.id);
      return reference(owner);
    }),
  );

  static Future<void> remove(AndroidCredentialOwner owner) => _queue.run(
    () => _invoke(owner, () async {
      await _backend.delete(owner.id);
      reauthenticationRequired.remove(owner.id);
    }),
  );

  /// Only the explicit full-app logout calls this. Recovery never does.
  /// The inventory contains IDs from this plugin's private files, not a
  /// machine-wide Keystore enumeration; it also finds interrupted writes.
  static Future<void> removeAllOwnedForLogout() => _queue.run(() async {
    try {
      for (final id in await _backend.listOwnedIds()) {
        await _backend.delete(id);
      }
      reauthenticationRequired.clear();
    } catch (_) {
      throw _report(
        const AndroidCredentialFailure(
          AndroidCredentialOwner('logout', 'Sign-out cleanup'),
          AndroidCredentialProblem.unavailable,
          'unknown',
        ),
      );
    }
  });

  /// No automatic reset. Cancellation performs no storage or transfer calls.
  /// The backend rechecks the revision and refuses to erase a healthy item.
  static Future<bool> resetAfterConfirmation(
    AndroidCredentialFailure failure, {
    required bool confirmed,
    required Future<void> Function(AndroidCredentialOwner) stopTransfers,
  }) async {
    if (!confirmed || !failure.canReset) return false;
    await _queue.run(
      () => _invoke(failure.owner, () async {
        try {
          final current = await _backend.read(failure.owner.id);
          if (current.revision != failure.revision || current.state != 'missing') {
            throw AndroidCredentialFailure(failure.owner, AndroidCredentialProblem.stale, current.revision);
          }
        } on PlatformException catch (error) {
          final details = error.details;
          if (!['permanent', 'reset_pending'].contains(error.code) ||
              details is! Map ||
              details['revision'] != failure.revision) {
            rethrow;
          }
        }
      }),
    );
    // Transfer cancellation may revoke its own per-task items. Do not hold
    // the store queue while calling an external lifecycle operation.
    await _invoke(failure.owner, () => stopTransfers(failure.owner));
    return _queue.run(
      () => _invoke(failure.owner, () async {
        final result = await _backend.reset(failure.owner.id, failure.revision);
        if (result.state != 'reauth') {
          throw AndroidCredentialFailure(failure.owner, AndroidCredentialProblem.unavailable, result.revision);
        }
        reauthenticationRequired.add(failure.owner.id);
        return true;
      }),
    );
  }
}
