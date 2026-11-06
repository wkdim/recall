final _clozePattern = RegExp(r'\{\{c::(.*?)\}\}');

/// Whether a template contains at least one cloze marker - used to warn a
/// user who ticks "cloze" but forgets the `{{c::...}}` syntax.
bool hasClozeMarker(String template) => _clozePattern.hasMatch(template);

/// The question view: every `{{c::answer}}` span replaced with a blank,
/// so the hidden part reads as something to recall, not just missing text.
String maskCloze(String template) {
  return template.replaceAllMapped(_clozePattern, (_) => '[...]');
}

/// The answer view: every `{{c::answer}}` span replaced with just the
/// answer text, so the full sentence reads naturally once revealed.
String revealCloze(String template) {
  return template.replaceAllMapped(_clozePattern, (m) => m.group(1) ?? '');
}
