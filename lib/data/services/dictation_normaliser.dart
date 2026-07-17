/// Undoes the recogniser's number formatting on dictated text.
///
/// iOS and Android both run inverse text normalisation over what they hear:
/// spoken "two" becomes `2`, "for" becomes `4`. That is correct for "buy 2
/// apples" and wrong for "need 2 buy milk" — the audio was understood, the
/// formatter picked the wrong surface form. No recogniser setting turns this
/// off, so it is undone here.
///
/// Every rule below needs a neighbouring word to fire. A bare digit is left
/// alone, because this assistant takes amounts and counts by voice and turning
/// the `2` in "buy 2 apples" into "to" would be a worse bug than the one being
/// fixed.
library;

/// Words that take an infinitive, so a `2` in front of one is "to".
const Set<String> _kInfinitiveVerbs = {
  'buy', 'get', 'call', 'pay', 'do', 'go', 'make', 'send', 'meet', 'take',
  'finish', 'read', 'watch', 'add', 'check', 'book', 'pick', 'visit', 'email',
  'text', 'ask', 'renew', 'cancel', 'order', 'return', 'fix', 'clean',
  'water', 'walk', 'submit', 'file', 'pack', 'charge', 'reply',
};

/// Words that take an infinitive after them, so a `2` behind one is "to".
const Set<String> _kIntentVerbs = {
  'need', 'needs', 'needed', 'want', 'wants', 'wanted', 'have', 'has', 'had',
  'got', 'gotta', 'going', 'go', 'remember', 'forgot', 'forget', 'try', 'plan',
  'planning', 'trying', 'like', 'love', 'hate', 'able', 'supposed', 'meant',
  'remind', 'reminded', 'told', 'tell', 'ought', 'used', 'wish',
};

/// Modals and markers that take a bare verb, so a "by" behind one is "buy".
const Set<String> _kBuyCues = {
  'to', 'gonna', 'wanna', 'gotta', 'must', 'should', 'shall', 'will', 'can',
  'could', 'would', 'might', 'lets', "let's", 'please', 'also',
};

/// Words after which "by" is the preposition, never the verb. Guards the
/// idioms — "by the way", "by tomorrow", "by hand" — that [_kBuyCues] would
/// otherwise rewrite.
const Set<String> _kNotBuy = {
  'the', 'then', 'now', 'hand', 'car', 'bus', 'train', 'plane', 'foot',
  'myself', 'yourself', 'himself', 'herself', 'accident', 'default', 'chance',
  'mistake', 'heart', 'phone', 'email', 'friday', 'monday', 'tuesday',
  'wednesday', 'thursday', 'saturday', 'sunday', 'tomorrow', 'today',
  'tonight', 'noon', 'midnight', 'week', 'month',
};

/// Determiners and pronouns that never follow a count, so a `4` in front of one
/// is "for".
const Set<String> _kForFollowers = {
  'the', 'a', 'an', 'me', 'my', 'you', 'your', 'us', 'our', 'him', 'his',
  'her', 'them', 'their', 'it', 'this', 'that', 'tomorrow', 'today', 'tonight',
  'later', 'now', 'dinner', 'lunch', 'breakfast', 'work', 'school', 'free',
};

/// [normaliseDictation] rewrites a transcript's misformatted homophones.
///
/// Runs on partial results as well as final ones, so the field the user is
/// watching never shows a `2` that is about to become a "to".
String normaliseDictation(String transcript) {
  if (transcript.isEmpty) return transcript;

  final tokens = transcript.split(' ');
  final words = tokens.map(_bareWord).toList(growable: false);

  for (var i = 0; i < tokens.length; i++) {
    final previous = i > 0 ? words[i - 1] : '';
    final next = i < tokens.length - 1 ? words[i + 1] : '';
    final replacement = _rewrite(words[i], previous, next);

    if (replacement != null) {
      tokens[i] = _reattach(tokens[i], words[i], replacement);
      // The next token reads this one as its `previous`, and the rules chain:
      // "need 2 by milk" only reaches "buy" once the `2` has become the "to"
      // that cues it.
      words[i] = replacement;
    }
  }

  return tokens.join(' ');
}

/// Returns what [word] should have been, or null to leave it alone.
String? _rewrite(String word, String previous, String next) {
  switch (word) {
    case '2':
      final isInfinitive = _kInfinitiveVerbs.contains(next);
      final isAfterIntent = _kIntentVerbs.contains(previous);
      return isInfinitive || isAfterIntent ? 'to' : null;
    case '4':
      // "4 the" is "for the"; "4 apples" is a count and stays a count.
      return _kForFollowers.contains(next) ? 'for' : null;
    case 'by':
      final hasCue = _kBuyCues.contains(previous);
      return hasCue && !_kNotBuy.contains(next) ? 'buy' : null;
    case '&':
      return 'and';
    case '@':
      return 'at';
    default:
      return null;
  }
}

/// Strips surrounding punctuation and case so a token can be matched.
///
/// The recogniser punctuates, and "need 2, buy milk" must still see `2`.
String _bareWord(String token) =>
    token.toLowerCase().replaceAll(RegExp(r"^[^a-z0-9@&']+|[^a-z0-9@&']+$"), '');

/// Puts [replacement] back into [token], keeping the punctuation that was
/// around the matched [word].
String _reattach(String token, String word, String replacement) {
  final start = token.toLowerCase().indexOf(word);
  if (start < 0) return replacement;

  return token.substring(0, start) +
      replacement +
      token.substring(start + word.length);
}
