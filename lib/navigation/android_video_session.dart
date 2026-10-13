import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../utils/platform_detector.dart';
import '../utils/video_player_navigation.dart';
import '../watch_together/services/watch_together_controller.dart';
import '../widgets/overlay_sheet.dart';

/// Keeps a handheld Android video in the profile scope while its route is
/// removed for browsing. The keyed screen and native player survive the move.
class AndroidVideoSession extends ChangeNotifier {
  AndroidVideoSession(this.host, this.navigator, this.builder, this.watchTogetherLease);

  final AndroidVideoPlayerHostState host;
  final NavigatorState navigator;
  final WidgetBuilder builder;
  final WatchPlaybackLease? watchTogetherLease;
  final _screenKey = GlobalKey();
  final _finished = Completer<bool?>();
  bool isMini = false;
  bool isClosed = false;
  VideoPlayerRoute? route;
  ValueListenable<bool>? videoReady;

  Widget get _screen => AndroidVideoSessionScope(
    session: this,
    child: KeyedSubtree(
      key: _screenKey,
      child: Builder(builder: builder),
    ),
  );

  Widget fullscreen(BuildContext context) =>
      ListenableBuilder(listenable: this, builder: (_, _) => isMini || isClosed ? const SizedBox.shrink() : _screen);

  VideoPlayerRoute createRoute() =>
      VideoPlayerRoute(builder: fullscreen, androidSession: this, watchTogetherLease: watchTogetherLease);

  Future<bool?> observeRoute(VideoPlayerRoute current, Future<bool?> popped) {
    route = current;
    unawaited(
      popped.then((value) {
        if (!isMini && identical(route, current)) close(value);
      }),
    );
    return _finished.future;
  }

  void minimize() {
    final current = route;
    if (isMini || isClosed || current == null || !current.isCurrent || !host.mounted) return;
    isMini = true;
    notifyListeners();
    host.refresh();
    // Both parents rebuild in this frame, moving the GlobalKey before the
    // old route is retired. Removing a route never disposes the live player.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed && isMini && current.isActive && navigator.mounted) navigator.removeRoute(current);
    });
  }

  void restore() {
    if (!isMini || isClosed || !navigator.mounted || !host.mounted) return;
    isMini = false;
    final existing = route;
    if (existing != null && existing.isActive && existing.isCurrent) {
      notifyListeners();
      host.refresh();
      return;
    }
    final next = createRoute();
    route = next;
    notifyListeners();
    host.refresh();
    unawaited(next.push(navigator));
  }

  void close([bool? result]) {
    if (isClosed) return;
    isClosed = true;
    final current = route;
    if (isMini && current != null && current.isActive && navigator.mounted) navigator.removeRoute(current);
    if (!_finished.isCompleted) _finished.complete(result);
    notifyListeners();
    host.release(this);
  }
}

class AndroidVideoSessionScope extends InheritedNotifier<AndroidVideoSession> {
  const AndroidVideoSessionScope({super.key, required AndroidVideoSession session, required super.child})
    : super(notifier: session);

  static AndroidVideoSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AndroidVideoSessionScope>()?.notifier;
}

class _AndroidVideoHostScope extends InheritedWidget {
  const _AndroidVideoHostScope({required this.host, required super.child});
  final AndroidVideoPlayerHostState host;

  @override
  bool updateShouldNotify(_AndroidVideoHostScope oldWidget) => host != oldWidget.host;
}

class AndroidVideoPlayerHost extends StatefulWidget {
  const AndroidVideoPlayerHost({super.key, required this.child});
  final Widget child;

  static AndroidVideoPlayerHostState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AndroidVideoHostScope>()?.host;

  static bool enabled(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.android && !PlatformDetector.isTV() && !PlatformDetector.isAutomotive();

  @override
  State<AndroidVideoPlayerHost> createState() => AndroidVideoPlayerHostState();
}

class AndroidVideoPlayerHostState extends State<AndroidVideoPlayerHost> {
  AndroidVideoSession? session;

  AndroidVideoSession createSession(NavigatorState navigator, WidgetBuilder builder, WatchPlaybackLease? lease) {
    final next = AndroidVideoSession(this, navigator, builder, lease);
    session = next;
    return next;
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void release(AndroidVideoSession old) {
    if (!identical(session, old)) return;
    session = null;
    refresh();
  }

  @override
  void dispose() {
    final old = session;
    session = null;
    old?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mini = session;
    return _AndroidVideoHostScope(
      host: this,
      child: ValueListenableBuilder<int>(
        valueListenable: OverlaySheetController.openSheetCount,
        builder: (context, openSheets, _) => LayoutBuilder(
          builder: (context, constraints) {
            final showMini = mini != null && mini.isMini && !mini.isClosed;
            final width = math.min(420.0, math.max(0.0, constraints.maxWidth - 24));
            final bottom = MediaQuery.paddingOf(context).bottom + 76;
            final videoRect = Rect.fromLTWH(
              constraints.maxWidth - 12 - width,
              constraints.maxHeight - bottom - 92 + (92 - 81) / 2,
              144,
              81,
            );
            return CustomPaint(
              // Android places the native video and subtitle surfaces beneath
              // Flutter. Clear the thumbnail rectangle after painting the browse
              // page, so its opaque Scaffold cannot cover the live picture.
              foregroundPainter: showMini && openSheets == 0
                  ? _AndroidVideoHolePainter(videoRect, mini.videoReady)
                  : null,
              child: Stack(
                children: [
                  widget.child,
                  if (showMini)
                    Positioned(
                      right: 12,
                      bottom: bottom,
                      width: width,
                      height: 92,
                      child: Offstage(offstage: openSheets > 0, child: mini._screen),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AndroidVideoHolePainter extends CustomPainter {
  _AndroidVideoHolePainter(this.rect, this.ready) : super(repaint: ready);
  final Rect rect;
  final ValueListenable<bool>? ready;

  @override
  void paint(Canvas canvas, Size size) {
    if (ready?.value == false) return;
    canvas.drawRect(rect, Paint()..blendMode = BlendMode.clear);
  }

  @override
  bool shouldRepaint(_AndroidVideoHolePainter oldDelegate) => rect != oldDelegate.rect || ready != oldDelegate.ready;
}
