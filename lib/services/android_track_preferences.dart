import 'package:flutter/foundation.dart';

import '../mpv/mpv.dart';
import '../media/media_source_info.dart';
import '../utils/android_track_metadata.dart';
export '../utils/android_track_metadata.dart';
import 'playback_subtitle_resolver.dart';
import 'subtitle_preference.dart';
import 'settings_service.dart';

/// Android-only defaults. Explicit player choices take precedence over these.
class AndroidTrackPreferences {
  final String? audioLanguage;
  final String? subtitleLanguage;
  final bool preferDialogue;

  const AndroidTrackPreferences({this.audioLanguage, this.subtitleLanguage, this.preferDialogue = true});

  static AndroidTrackPreferences? get current {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final settings = SettingsService.instanceOrNull;
    if (settings == null) return null;
    return AndroidTrackPreferences(
      audioLanguage: settings.read(SettingsService.androidAudioLanguage),
      subtitleLanguage: settings.read(SettingsService.androidSubtitleLanguage),
      preferDialogue: settings.read(SettingsService.androidPreferDialogueSubtitles),
    );
  }

  AudioTrack? selectAudio(List<AudioTrack> tracks) {
    final wanted = audioLanguage;
    if (wanted == null) return null;
    final matches = tracks
        .where(
          (track) =>
              track.id != 'auto' && track.id != 'no' && androidTrackLanguage(track.language, track.title) == wanted,
        )
        .toList();
    matches.sort((a, b) => _audioRank(b).compareTo(_audioRank(a)));
    return matches.firstOrNull;
  }

  SubtitleTrack? selectSubtitle(List<SubtitleTrack> tracks) {
    final wanted = subtitleLanguage;
    if (wanted == null) return null;
    final matches = tracks
        .where(
          (track) =>
              track.id != 'auto' && track.id != 'no' && androidTrackLanguage(track.language, track.title) == wanted,
        )
        .toList();
    if (matches.isEmpty) return null;
    if (preferDialogue) {
      matches.removeWhere((track) {
        final role = androidSubtitleRole(track.title, forced: track.isForced);
        return role == AndroidSubtitleRole.signs || role == AndroidSubtitleRole.forced;
      });
      // A signs-only translation cannot satisfy a dialogue preference.
      if (matches.isEmpty) return SubtitleTrack.off;
    }
    matches.sort((a, b) => _subtitleRank(b).compareTo(_subtitleRank(a)));
    return matches.first;
  }

  int _audioRank(AudioTrack track) =>
      (androidTrackTitleTokens(track.title).contains('commentary') ? -10 : 0) + (track.isDefault ? 1 : 0);

  int _subtitleRank(SubtitleTrack track) =>
      (preferDialogue && androidSubtitleRole(track.title, forced: track.isForced) == AndroidSubtitleRole.dialogue
          ? 10
          : 0) +
      (track.isDefault ? 1 : 0);
}

int? androidDefaultAudioStreamId(MediaSourceInfo? source) {
  if (source == null) return null;
  final selected = AndroidTrackPreferences.current?.selectAudio(PlaybackSubtitleResolver.audioTracksForSource(source));
  return selected == null ? null : int.tryParse(selected.id.replaceFirst('source:', ''));
}

SubtitlePreference? androidDefaultSubtitlePreference(MediaSourceInfo? source) {
  if (source == null) return null;
  final selected = AndroidTrackPreferences.current?.selectSubtitle([
    for (final row in source.subtitleTracks) PlaybackSubtitleResolver.subtitleTrackForSource(row),
  ]);
  return SubtitlePreference.trackOrNull(selected);
}

/// Source IDs selected from this item's catalog need no cross-item matching.
/// Jellyfin uses -1 for an explicit subtitle-off request.
int? androidDefaultSubtitleStreamId(MediaSourceInfo? source) {
  return switch (androidDefaultSubtitlePreference(source)) {
    SubtitleOffPreference() => -1,
    SubtitleTrackPreference(:final track) => int.tryParse(track.id.replaceFirst('source:', '')),
    _ => null,
  };
}
