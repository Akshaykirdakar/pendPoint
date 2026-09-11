/// Deterministic English-to-Devanagari transliteration for product names.
String transliterateMarathi(String input) {
  const known = {
    'milk': 'मिल्क',
    'booster': 'बूस्टर',
    'feed': 'फीड',
    'cake': 'केक',
    'premium': 'प्रीमियम',
    'gold': 'गोल्ड',
    'plus': 'प्लस',
    'mix': 'मिक्स'
  };
  return input.splitMapJoin(RegExp(r'[A-Za-z]+'),
      onMatch: (m) {
        final original = m[0]!;
        if (known.containsKey(original.toLowerCase())) {
          return known[original.toLowerCase()]!;
        }
        var value = original.toLowerCase();
        const map = {
          'tion': 'शन',
          'sh': 'श',
          'ch': 'च',
          'th': 'थ',
          'ph': 'फ',
          'oo': 'ू',
          'ee': 'ी',
          'ai': 'े',
          'ay': 'े',
          'a': 'अ',
          'e': 'े',
          'i': 'ि',
          'o': 'ो',
          'u': 'ु',
          'b': 'ब',
          'c': 'क',
          'd': 'ड',
          'f': 'फ',
          'g': 'ग',
          'h': 'ह',
          'j': 'ज',
          'k': 'क',
          'l': 'ल',
          'm': 'म',
          'n': 'न',
          'p': 'प',
          'q': 'क',
          'r': 'र',
          's': 'स',
          't': 'ट',
          'v': 'व',
          'w': 'व',
          'x': 'क्स',
          'y': 'य',
          'z': 'झ'
        };
        for (final key in map.keys) {
          value = value.replaceAll(key, map[key]!);
        }
        return value;
      },
      onNonMatch: (s) => s);
}
