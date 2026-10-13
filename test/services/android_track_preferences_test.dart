import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/media/media_stream.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/services/android_track_preferences.dart';
import 'package:plezy/services/playback_subtitle_resolver.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/subtitle_preference.dart';
import 'package:plezy/services/track_selection_service.dart';
import 'package:plezy/widgets/android_episode_tracks.dart';
import 'package:plezy/utils/track_label_builder.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const prefs = AndroidTrackPreferences(audioLanguage: 'ja', subtitleLanguage: 'en');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    SettingsService.resetForTesting();
  });

  test('normalizes Japanese and English codes and title evidence', () {
    expect(androidTrackLanguage('jpn', null), 'ja');
    expect(androidTrackLanguage('en-US', null), 'en');
    expect(androidTrackLanguage('English', null), 'en');
    expect(androidTrackLanguage('und', 'English Full'), 'en');
    expect(androidTrackLanguage(null, 'Japanese (original)'), 'ja');
    expect(androidTrackLanguage('fr', 'English Full'), 'fr');
    expect(androidTrackLanguage('und', 'Unknown'), isNull);
    expect(androidTrackLanguage(null, 'Japanese / English'), isNull);
  });

  test('prefers Japanese original audio over commentary and English dub', () {
    expect(
      prefs.selectAudio(const [
        AudioTrack(id: '1', language: 'eng', isDefault: true),
        AudioTrack(id: '2', language: 'jpn', title: 'Commentary', isDefault: true),
        AudioTrack(id: '3', language: 'ja', title: 'Original'),
      ])?.id,
      '3',
    );
  });

  test('prefers full dialogue over server-default signs and forced English', () {
    expect(
      prefs.selectSubtitle(const [
        SubtitleTrack(id: '1', language: 'eng', title: 'Signs & Songs', isDefault: true),
        SubtitleTrack(id: '2', language: 'en', title: 'Forced', isForced: true),
        SubtitleTrack(id: '3', language: 'und', title: 'English Full dialogue + signs'),
      ])?.id,
      '3',
    );
  });

  test('allows an ordinary English track without inventing a dialogue label', () {
    expect(androidSubtitleRole('Unknown'), AndroidSubtitleRole.unspecified);
    expect(prefs.selectSubtitle(const [SubtitleTrack(id: '2', language: 'eng', title: 'Unknown')])?.id, '2');
  });

  test('signs alone cannot satisfy full-dialogue preference', () {
    expect(prefs.selectSubtitle(const [SubtitleTrack(id: '2', language: 'en', title: 'Signs')]), SubtitleTrack.off);
    expect(prefs.selectSubtitle(const [SubtitleTrack(id: '2', language: 'und', title: 'Unknown')]), isNull);
    expect(
      const AndroidTrackPreferences(
        subtitleLanguage: 'en',
        preferDialogue: false,
      ).selectSubtitle(const [SubtitleTrack(id: '2', language: 'en', title: 'Signs')])?.id,
      '2',
    );
  });

  test('episode labels retain roles, codec, unknown language, and stream identity', () {
    final full = androidEpisodeTrackLabel(
      const MediaStream(
        id: '3',
        index: 3,
        kind: MediaStreamKind.subtitle,
        languageCode: 'eng',
        title: 'Full',
        codec: 'ass',
      ),
    );
    expect(full, contains('English'));
    expect(full, contains('Full dialogue'));
    expect(full, contains('ASS'));
    expect(full, contains('#3'));
    expect(
      androidEpisodeTrackLabel(
        const MediaStream(id: '7', kind: MediaStreamKind.subtitle, languageCode: 'und', title: 'Unknown'),
      ),
      contains('Unknown language'),
    );
  });

  test('Android unknown player tracks get distinct numbered labels', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final a = TrackLabelBuilder.subtitleLabel(language: 'und', title: 'Unknown', index: 0);
    final b = TrackLabelBuilder.subtitleLabel(language: 'und', title: 'Unknown', index: 1);
    expect(a.primary, 'Unknown (#1)');
    expect(b.primary, 'Unknown (#2)');
  });

  test('Android episode carry keeps dialogue and signs in their own role', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const full = SubtitleIntent(language: 'en', forced: false, title: 'Full');
    const signs = SubtitleIntent(language: 'en', forced: false, title: 'Signs & Songs');
    const tracks = [
      SubtitleTrack(id: '1', language: 'en', title: 'Signs & Songs'),
      SubtitleTrack(id: '2', language: 'en', title: 'Complete dialogue'),
    ];
    expect(findNativeTrackForIntent(full, tracks)?.id, '2');
    expect(findNativeTrackForIntent(full, [tracks.first]), isNull);
    expect(findNativeTrackForIntent(signs, tracks)?.id, '1');
  });

  test('local Android defaults precede server picks but manual choices win', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    resetSharedPreferencesForTest();
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.androidAudioLanguage, 'ja');
    await settings.write(SettingsService.androidSubtitleLanguage, 'en');
    final source = MediaSourceInfo(
      videoUrl: '',
      audioTracks: [
        MediaAudioTrack(id: 1, languageCode: 'eng', selected: true),
        MediaAudioTrack(id: 2, languageCode: 'jpn', selected: false),
      ],
      subtitleTracks: [
        MediaSubtitleTrack(id: 3, languageCode: 'eng', title: 'Signs & Songs', selected: true, forced: false),
        MediaSubtitleTrack(id: 4, languageCode: 'eng', title: 'Full', selected: false, forced: false),
      ],
      chapters: const [],
    );
    final metadata = testMediaItem(backend: MediaBackend.plex, kind: MediaKind.episode);
    final service = TrackSelectionService(metadata: metadata, plexMediaInfo: source);
    final audio = PlaybackSubtitleResolver.audioTracksForSource(source);
    final subtitles = [for (final row in source.subtitleTracks) PlaybackSubtitleResolver.subtitleTrackForSource(row)];
    expect(service.selectAudioTrack(audio, null)?.track.id, 'source:2');
    expect(service.selectSubtitleTrack(subtitles, null, audio.last)?.track.id, 'source:4');
    expect(service.selectAudioTrack(audio, audio.first)?.track.id, 'source:1');
    expect(
      service.selectSubtitleTrack(subtitles, const SubtitlePreference.off(), audio.last)?.track,
      SubtitleTrack.off,
    );
    expect(
      service.selectSubtitleTrack(subtitles, SubtitlePreference.track(subtitles.first), audio.last)?.track.id,
      'source:3',
    );
    expect(androidDefaultAudioStreamId(source), 2);
    expect(androidDefaultSubtitlePreference(source), SubtitlePreference.track(subtitles.last));
    expect(androidDefaultSubtitleStreamId(source), 4);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(service.selectAudioTrack(audio, null)?.track.id, 'source:1');
    expect(service.selectSubtitleTrack(subtitles, null, audio.first)?.track.id, 'source:3');
    expect(androidDefaultAudioStreamId(source), isNull);
    expect(androidDefaultSubtitlePreference(source), isNull);
    expect(androidDefaultSubtitleStreamId(source), isNull);
  });
}
