import 'dart:async';

import 'package:flutter/material.dart';

import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../media/media_stream.dart';
import '../services/android_track_preferences.dart';
import '../utils/language_codes.dart';

/// Read-only metadata for episode cards; never negotiates a playback stream.
class AndroidEpisodeTracks extends StatefulWidget {
  final MediaItem episode;
  final MediaServerClient? client;
  final bool isOffline;

  const AndroidEpisodeTracks({super.key, required this.episode, this.client, required this.isOffline});

  @override
  State<AndroidEpisodeTracks> createState() => _AndroidEpisodeTracksState();
}

class _AndroidEpisodeTracksState extends State<AndroidEpisodeTracks> {
  MediaItem? _fetched;
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(AndroidEpisodeTracks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episode != widget.episode ||
        oldWidget.client != widget.client ||
        oldWidget.isOffline != widget.isOffline) {
      _generation++;
      _fetched = null;
      _loadIfNeeded();
    }
  }

  static List<MediaStream> _streams(MediaItem item) => [
    for (final version in item.mediaVersions ?? [])
      for (final part in version.parts) ...part.streams,
  ];

  void _loadIfNeeded() {
    _loading = false;
    if (widget.isOffline || widget.client == null || _streams(widget.episode).isNotEmpty) return;
    _loading = true;
    final generation = _generation;
    final client = widget.client!;
    final itemId = widget.episode.id;
    unawaited(() async {
      MediaItem? fetched;
      try {
        fetched = await client.fetchItem(itemId);
      } catch (_) {
        // Metadata failures must not make the episode unplayable.
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _fetched = fetched;
        _loading = false;
      });
    }());
  }

  @override
  Widget build(BuildContext context) {
    final streams = _streams(_fetched ?? widget.episode);
    final audio = <String>{};
    final subtitles = <String>{};
    for (final stream in streams) {
      final label = androidEpisodeTrackLabel(stream);
      if (stream.kind == MediaStreamKind.audio) audio.add(label);
      if (stream.kind == MediaStreamKind.subtitle) subtitles.add(label);
    }
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12);
    if (streams.isEmpty) {
      return Text(_loading ? 'Loading audio and subtitles…' : 'Audio/subtitle info unavailable', style: style);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Audio: ${audio.isEmpty ? 'None listed' : audio.join(', ')}', style: style),
        Text('Subtitles: ${subtitles.isEmpty ? 'None listed' : subtitles.join(', ')}', style: style),
        if ((_fetched ?? widget.episode).mediaVersions?.length case final int count when count > 1)
          Text('Tracks across $count versions; availability depends on the version.', style: style),
      ],
    );
  }
}

String androidEpisodeTrackLabel(MediaStream stream) {
  final title = stream.title?.trim();
  final language = androidTrackLanguage(stream.languageCode ?? stream.language, title ?? stream.displayTitle);
  final name = language == null ? 'Unknown language' : LanguageCodes.getDisplayName(language);
  final details = <String>[];
  if (stream.kind == MediaStreamKind.subtitle) {
    switch (androidSubtitleRole(title ?? stream.displayTitle, forced: stream.forced)) {
      case AndroidSubtitleRole.dialogue:
        details.add('Full dialogue');
      case AndroidSubtitleRole.signs:
        details.add('Signs/Songs');
      case AndroidSubtitleRole.forced:
        details.add('Forced');
      case AndroidSubtitleRole.unspecified:
        break;
    }
    if (title != null && title.isNotEmpty && title.toLowerCase() != name.toLowerCase()) details.add(title);
    if (stream.codec?.isNotEmpty == true) details.add(stream.codec!.toUpperCase());
    details.add('#${stream.index ?? stream.id}');
  } else if (language == null || (title?.toLowerCase().contains('commentary') ?? false)) {
    if (title?.isNotEmpty == true) details.add(title!);
    details.add('#${stream.index ?? stream.id}');
  }
  return details.isEmpty ? name : '$name (${details.join(' · ')})';
}
