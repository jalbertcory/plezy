import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_icon.dart';

class AndroidVideoMiniPlayer extends StatefulWidget {
  const AndroidVideoMiniPlayer({
    super.key,
    required this.video,
    required this.title,
    required this.playing,
    required this.onPlayPause,
    required this.onClose,
    required this.onRestore,
  });

  final Widget video;
  final String title;
  final bool playing;
  final VoidCallback? onPlayPause;
  final VoidCallback onClose;
  final VoidCallback onRestore;

  @override
  State<AndroidVideoMiniPlayer> createState() => _AndroidVideoMiniPlayerState();
}

class _AndroidVideoMiniPlayerState extends State<AndroidVideoMiniPlayer> {
  double _drag = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onRestore,
    onVerticalDragStart: (_) => _drag = 0,
    onVerticalDragUpdate: (details) => _drag += details.primaryDelta ?? 0,
    onVerticalDragEnd: (details) {
      if (_drag < -40 || (details.primaryVelocity ?? 0) < -300) widget.onRestore();
    },
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
      ),
      child: Row(
        children: [
          SizedBox(width: 144, height: 81, child: widget.video),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 44,
                width: 44,
                child: IconButton(
                  tooltip: widget.playing ? 'Pause video' : 'Play video',
                  onPressed: widget.onPlayPause,
                  icon: AppIcon(
                    widget.playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                width: 44,
                child: IconButton(
                  tooltip: 'Close video',
                  onPressed: widget.onClose,
                  icon: const AppIcon(Symbols.close_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
