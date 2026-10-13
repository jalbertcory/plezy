import 'package:flutter/material.dart';

import '../focus/focusable_button.dart';
import 'dialog_action_button.dart';
import '../services/android_credentials/android_credential_store.dart';
import '../services/android_credentials/android_credential_recovery.dart';

/// Android bootstrap UI. A reset is a separate, cancellable confirmation.
class AndroidCredentialRecoveryView extends StatefulWidget {
  const AndroidCredentialRecoveryView({
    super.key,
    required this.failure,
    required this.retriesRemaining,
    required this.onRetry,
    required this.onContinue,
    this.stopTransfers = stopAndroidCredentialTransfers,
  });
  final AndroidCredentialFailure failure;
  final int retriesRemaining;
  final VoidCallback onRetry;
  final VoidCallback onContinue;
  final Future<void> Function(AndroidCredentialOwner) stopTransfers;
  @override
  State<AndroidCredentialRecoveryView> createState() => _AndroidCredentialRecoveryViewState();
}

class _AndroidCredentialRecoveryViewState extends State<AndroidCredentialRecoveryView> {
  bool _busy = false;
  bool _reset = false;
  AndroidCredentialFailure? _resetFailure;
  String? _message;

  Future<void> _confirmReset() async {
    if (_busy) return;
    final failure = _resetFailure ?? widget.failure;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset this saved sign-in?'),
        content: Text(
          '${failure.owner.label}\n\n'
          'Only this saved credential will be cleared. You will need to sign in again. '
          'Transfers using this sign-in will stop. Other accounts, profiles, downloaded media, '
          'settings, and legacy recovery values will stay on this device.',
        ),
        actions: [
          DialogActionButton(autofocus: true, onPressed: () => Navigator.pop(context, false), label: 'Cancel'),
          DialogActionButton(onPressed: () => Navigator.pop(context, true), label: 'Reset this sign-in'),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final reset = await AndroidCredentialStore.resetAfterConfirmation(
        failure,
        confirmed: true,
        stopTransfers: widget.stopTransfers,
      );
      if (mounted) setState(() => _reset = reset);
    } on AndroidCredentialFailure catch (error) {
      if (mounted) {
        setState(() {
          _resetFailure = error;
          _message = error.problem == AndroidCredentialProblem.stale
              ? 'The saved sign-in changed. Check again before taking another action.'
              : 'The reset could not finish. The store may be unavailable, or a download could not be safely assigned to this sign-in. No other sign-in was reset.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'The affected downloads could not be stopped. The saved sign-in was not reset.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = _resetFailure ?? widget.failure;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _reset ? 'Saved sign-in reset' : 'Saved sign-in unavailable',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(failure.owner.label),
              const SizedBox(height: 12),
              Text(
                _reset
                    ? 'Continue to sign in again. For a profile service, select that profile and reconnect the service in Settings. Other saved sign-ins are unchanged.'
                    : failure.canReset
                    ? 'Android cannot use the key for this saved sign-in. Repeated retries will not repair a lost key. Nothing has been erased. You can reset only this sign-in and authenticate again.'
                    : 'The credential store may be temporarily locked or unavailable. Unlock the device and check again. No reset is offered for a temporary or unknown failure.',
              ),
              if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!)),
              if (_busy) const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
              const SizedBox(height: 20),
              if (_reset)
                FocusableButton(
                  autofocus: true,
                  onPressed: widget.onContinue,
                  child: FilledButton(onPressed: widget.onContinue, child: const Text('Continue to sign in')),
                )
              else ...[
                if (widget.retriesRemaining > 0)
                  FocusableButton(
                    autofocus: true,
                    onPressed: _busy ? null : widget.onRetry,
                    child: OutlinedButton(
                      onPressed: _busy ? null : widget.onRetry,
                      child: Text('Check again (${widget.retriesRemaining} remaining)'),
                    ),
                  )
                else
                  const Text(
                    'No more checks this session. Close and reopen Plezy after unlocking the device. Your data has not been cleared.',
                  ),
                if (failure.canReset)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FocusableButton(
                      onPressed: _busy ? null : _confirmReset,
                      child: OutlinedButton(
                        onPressed: _busy ? null : _confirmReset,
                        child: Text(
                          failure.problem == AndroidCredentialProblem.resetPending
                              ? 'Finish confirmed reset…'
                              : 'Reset this sign-in…',
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
