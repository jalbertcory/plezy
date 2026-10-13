import 'language_codes.dart';

enum AndroidSubtitleRole { dialogue, signs, forced, unspecified }

Set<String> androidTrackTitleTokens(String? text) =>
    (text ?? '').toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((word) => word.isNotEmpty).toSet();

/// Declared language wins. A clear, single language name in a title can fill
/// missing metadata; a wholly unlabelled track stays unknown.
String? androidTrackLanguage(String? language, String? title) {
  final declared = LanguageCodes.getIso6391Code(language ?? '');
  if (declared != null) return declared;
  for (final entry in LanguageCodes.getAllLanguages()) {
    if (entry.name.toLowerCase() == language?.trim().toLowerCase()) return entry.code;
  }
  final tokens = androidTrackTitleTokens(title);
  final matches = <String>{};
  for (final entry in LanguageCodes.getAllLanguages()) {
    final name = entry.name.toLowerCase();
    if (!name.contains(' ') && tokens.contains(name)) matches.add(entry.code);
  }
  for (final code in ['ja', 'en']) {
    if (LanguageCodes.getVariations(code).any(tokens.contains)) matches.add(code);
  }
  if (tokens.contains('japanese') || tokens.contains('jpn')) matches.add('ja');
  if (tokens.contains('english') || tokens.contains('eng')) matches.add('en');
  return matches.length == 1 ? matches.single : null;
}

AndroidSubtitleRole androidSubtitleRole(String? title, {bool forced = false}) {
  final words = androidTrackTitleTokens(title);
  if (forced || words.contains('forced')) return AndroidSubtitleRole.forced;
  // Full tracks may explicitly say "dialogue + signs and songs".
  if (words.any(['full', 'dialogue', 'dialog', 'complete', 'sdh', 'cc'].contains)) {
    return AndroidSubtitleRole.dialogue;
  }
  if (words.any(['sign', 'signs', 'song', 'songs'].contains)) return AndroidSubtitleRole.signs;
  return AndroidSubtitleRole.unspecified;
}
