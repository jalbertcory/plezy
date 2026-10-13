import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/android_credentials/android_credential_bindings.dart';
import 'package:plezy/services/android_credentials/android_credential_recovery.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/utils/active_client_scope.dart';

void main() {
  test('two accounts sharing one server remain separate', () {
    final owner = connectionCredentialOwner('server/user-a', 'accessToken', 'Fake A', {'server'});
    expect(
      androidTransferOwnership(owner, taskId: 'fake-task', serverId: 'server', clientScopeId: 'server/user-a'),
      AndroidTransferOwnership.selected,
    );
    expect(
      androidTransferOwnership(owner, taskId: 'fake-task', serverId: 'server', clientScopeId: 'server/user-b'),
      AndroidTransferOwnership.unrelated,
    );
  });
  test('missing transfer provenance blocks reset instead of broad cleanup', () {
    final owner = connectionCredentialOwner('server/user-a', 'accessToken', 'Fake A', {'server'});
    expect(
      androidTransferOwnership(owner, taskId: 'fake-task', serverId: 'server', clientScopeId: null),
      AndroidTransferOwnership.ambiguous,
    );
    expect(
      androidTransferOwnership(owner, taskId: 'fake-task', serverId: 'other', clientScopeId: null),
      AndroidTransferOwnership.unrelated,
    );
  });
  test('Plex Home provenance distinguishes account and profile', () {
    final a = plexHomeProfileId(accountConnectionId: 'account-a', homeUserUuid: '0123456789abcdef');
    final b = plexHomeProfileId(accountConnectionId: 'account-b', homeUserUuid: '0123456789abcdef');
    final owner = profileCredentialOwner(a, 'account-a', servers: {'server'});
    String scope(String profile) => PlexProfileScopeId(serverId: ServerId('server'), profileId: profile);
    expect(
      androidTransferOwnership(owner, taskId: 'fake-task', serverId: 'server', clientScopeId: scope(a)),
      AndroidTransferOwnership.selected,
    );
    expect(
      androidTransferOwnership(owner, taskId: 'fake-task', serverId: 'server', clientScopeId: scope(b)),
      AndroidTransferOwnership.unrelated,
    );
    expect(
      androidTransferOwnership(owner, taskId: 'fake-task', serverId: 'server', clientScopeId: scope('local-profile')),
      AndroidTransferOwnership.ambiguous,
    );
  });
}
