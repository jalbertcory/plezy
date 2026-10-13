import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/navigation/android_video_session.dart';
import 'package:plezy/providers/playback_state_provider.dart';
import 'package:plezy/screens/video_player_screen.dart';
import 'package:plezy/services/playback_coordinator.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/widgets/android_video_mini_player.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/media_items.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/pump.dart';
import '../../test_helpers/watch_together_fakes.dart';

void main() {
  testWidgets('real player screen survives mini moves and closes through playback retirement', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    final startupHold = Completer<void>();
    Future<void> holdStartup() => startupHold.future;
    PlaybackCoordinator.instance.registerMusicSession(stopAndDispose: holdStartup);
    final player = _MiniPlayer();
    final screenKey = GlobalKey<VideoPlayerScreenState>();
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext browseContext;
    try {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => PlaybackStateProvider(),
          child: MaterialApp(
            home: AndroidVideoPlayerHost(
              child: Navigator(
                key: navigator,
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) {
                    browseContext = context;
                    return const Scaffold(body: Text('Browse episodes'));
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final host = AndroidVideoPlayerHost.maybeOf(browseContext)!;
      final session = host.createSession(
        navigator.currentState!,
        (_) => VideoPlayerScreen(key: screenKey, metadata: testMediaItem(), isOffline: true),
        null,
      );
      final finished = session.createRoute().push(navigator.currentState!);
      await tester.pump();
      final originalState = screenKey.currentState!;
      originalState.player = player;
      session.minimize();
      await tester.pump();
      await tester.pump();
      expect(find.byType(AndroidVideoMiniPlayer), findsOneWidget);
      expect(find.text('Browse episodes'), findsOneWidget);
      expect(screenKey.currentState, same(originalState));
      expect(screenKey.currentState!.player, same(player));
      expect(player.disposed, isFalse);

      await tester.drag(find.byType(AndroidVideoMiniPlayer), const Offset(0, -80));
      await tester.pump();
      await tester.pump();
      expect(screenKey.currentState, same(originalState));
      expect(find.byType(AndroidVideoMiniPlayer), findsNothing);
      session.minimize();
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Close video'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(screenKey.currentState, isNull);
      expect(await finished, isTrue);
      expect(host.session, isNull);
      expect(find.text('Browse episodes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      PlaybackCoordinator.instance.unregisterMusicSession(holdStartup);
      startupHold.complete();
      var retired = false;
      final retirement = PlaybackCoordinator.instance.shutdownVideo().whenComplete(() => retired = true);
      await pumpUntil(tester, () => retired);
      await retirement;
      debugDefaultTargetPlatformOverride = null;
      SettingsService.resetForTesting();
    }
    expect(player.disposed, isTrue);
  });
}

class _MiniPlayer extends FakeSyncPlayer {
  _MiniPlayer() : super(playing: true);
  @override
  Future<void> updateFrame() async {}
  @override
  Future<String?> getProperty(String name) async => null;
  @override
  Future<void> abandonAudioFocus() async {}
}
