import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/navigation/android_video_session.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/android_video_mini_player.dart';
import 'package:plezy/widgets/overlay_sheet.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TvDetectionService.debugReset();
  });

  testWidgets('minimize, browse, and restore retain one screen and pending session future', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext browseContext;
    var starts = 0;
    var disposals = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AndroidVideoPlayerHost(
          child: Navigator(
            key: navigator,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => Builder(
                builder: (context) {
                  browseContext = context;
                  return const Scaffold(body: Text('Episodes'));
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
      (_) => _TestPlayer(onStart: () => starts++, onDispose: () => disposals++),
      null,
    );
    var finished = false;
    final result = session.createRoute().push(navigator.currentState!);
    unawaited(result.then((_) => finished = true));
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(hasMinimizedAndroidVideo(browseContext), isFalse);
    await tester.tap(find.text('Minimize'));
    await tester.pumpAndSettle();
    expect(hasMinimizedAndroidVideo(browseContext), isTrue);
    expect(find.text('Episodes'), findsOneWidget);
    expect(find.byType(AndroidVideoMiniPlayer), findsOneWidget);
    expect(starts, 1);
    expect(disposals, 0);
    expect(finished, isFalse);

    final sheet = OverlaySheetController.showAdaptive<void>(
      browseContext,
      builder: (_) => const SizedBox(height: 160, child: Text('Episode actions')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Episode actions'), findsOneWidget);
    expect(find.byType(AndroidVideoMiniPlayer), findsNothing);
    expect(starts, 1);
    expect(disposals, 0);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await sheet;
    expect(find.byType(AndroidVideoMiniPlayer), findsOneWidget);
    expect(starts, 1);

    unawaited(
      navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Another show')))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Another show'), findsOneWidget);
    expect(find.byType(AndroidVideoMiniPlayer), findsOneWidget);
    await tester.drag(find.byType(AndroidVideoMiniPlayer), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(find.text('Minimize'), findsOneWidget);
    expect(hasMinimizedAndroidVideo(browseContext), isFalse);
    expect(starts, 1);
    expect(disposals, 0);
    expect(finished, isFalse);
    navigator.currentState!.pop(true);
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(disposals, 1);
    expect(find.text('Another show'), findsOneWidget);
  });

  testWidgets('other platforms never see a minimized Android video host', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: AndroidVideoPlayerHost(
          child: Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(androidVideoHostOf(context), isNull);
    expect(hasMinimizedAndroidVideo(context), isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('closing a mini player completes and disposes exactly once', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext browseContext;
    var disposed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AndroidVideoPlayerHost(
          child: Navigator(
            key: navigator,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => Builder(
                builder: (context) {
                  browseContext = context;
                  return const Scaffold();
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
      (_) => _TestPlayer(onStart: () {}, onDispose: () => disposed++),
      null,
    );
    final result = session.createRoute().push(navigator.currentState!);
    await tester.pumpAndSettle();
    session.minimize();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close video'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(disposed, 1);
    expect(host.session, isNull);
    expect(find.byType(AndroidVideoMiniPlayer), findsNothing);
  });

  testWidgets('mini native video clears opaque browse content only inside its thumbnail', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final painted = GlobalKey();
    late BuildContext browseContext;
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: painted,
          child: AndroidVideoPlayerHost(
            child: Navigator(
              key: navigator,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) {
                  browseContext = context;
                  return const Scaffold(backgroundColor: Colors.green);
                },
              ),
            ),
          ),
        ),
      ),
    );
    final session = AndroidVideoPlayerHost.maybeOf(
      browseContext,
    )!.createSession(navigator.currentState!, (_) => _TestPlayer(onStart: () {}, onDispose: () {}), null);
    unawaited(session.createRoute().push(navigator.currentState!));
    await tester.pumpAndSettle();
    session.minimize();
    await tester.pumpAndSettle();
    final image = await tester.runAsync(
      () => (painted.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(),
    );
    final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.rawRgba));
    final video = tester.getRect(
      find.descendant(of: find.byType(AndroidVideoMiniPlayer), matching: find.byType(SizedBox)).first,
    );
    final center = video.center;
    final thumbnailAlpha = bytes!.getUint8((center.dy.floor() * image!.width + center.dx.floor()) * 4 + 3);
    expect(thumbnailAlpha, 0, reason: 'native video needs a transparent hole through the Flutter page');
    expect(bytes.getUint8(3), 255, reason: 'the rest of the browse page stays opaque');
    image.dispose();
    session.close();
    await tester.pumpAndSettle();
  });

  testWidgets('mini player is limited to Android handhelds', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(AndroidVideoPlayerHost.enabled(context), isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(AndroidVideoPlayerHost.enabled(context), isTrue);
    TvDetectionService.debugSetAppleTVOverride(true);
    expect(AndroidVideoPlayerHost.enabled(context), isFalse);
    TvDetectionService.debugSetAppleTVOverride(false);
    TvDetectionService.debugSetAutomotiveOverride(true);
    expect(AndroidVideoPlayerHost.enabled(context), isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}

class _TestPlayer extends StatefulWidget {
  const _TestPlayer({required this.onStart, required this.onDispose});
  final VoidCallback onStart;
  final VoidCallback onDispose;
  @override
  State<_TestPlayer> createState() => _TestPlayerState();
}

class _TestPlayerState extends State<_TestPlayer> {
  @override
  void initState() {
    super.initState();
    widget.onStart();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = AndroidVideoSessionScope.maybeOf(context)!;
    if (session.isMini) {
      return AndroidVideoMiniPlayer(
        video: const SizedBox(),
        title: 'Playing episode',
        playing: true,
        onPlayPause: () {},
        onClose: () => session.close(true),
        onRestore: session.restore,
      );
    }
    return Scaffold(
      body: TextButton(onPressed: session.minimize, child: const Text('Minimize')),
    );
  }
}
