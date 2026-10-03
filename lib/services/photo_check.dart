import 'dart:typed_data';

/// The same limits the Storage rules enforce (image/jpeg|png|webp, under
/// 5 MB), checked before uploading so the user sees why instead of a
/// "permission denied".
const int maxPhotoBytes = 5 * 1024 * 1024;

/// The real image type of [bytes] from its file signature — 'jpg', 'png'
/// or 'webp' — or null when it is not one of those.
String? photoTypeOf(Uint8List bytes) {
  bool at(int offset, List<int> sig) {
    if (bytes.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[offset + i] != sig[i]) return false;
    }
    return true;
  }

  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'jpg';
  if (at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'png';
  }
  if (at(0, const [0x52, 0x49, 0x46, 0x46]) && // RIFF
      at(8, const [0x57, 0x45, 0x42, 0x50])) {
    return 'webp';
  }
  return null;
}

/// Why [bytes] cannot be uploaded as a photo, or null when it can.
String? photoProblem(Uint8List bytes) {
  if (bytes.isEmpty || photoTypeOf(bytes) == null) {
    return 'फक्त JPG, PNG किंवा WEBP फोटो चालतो · Only JPG, PNG or WEBP photos can be uploaded';
  }
  if (bytes.length >= maxPhotoBytes) {
    return 'फोटो ५ MB पेक्षा लहान हवा · The photo must be smaller than 5 MB';
  }
  return null;
}

/// The Storage object path inside a Firebase download URL
/// (`…/o/<encoded path>?alt=media…`), or null for any other URL.
String? storagePathOfUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final segs = uri.pathSegments;
  final o = segs.indexOf('o');
  if (o < 0 || o + 1 >= segs.length) return null;
  // pathSegments are already decoded once; the object path is one segment.
  return segs.sublist(o + 1).join('/');
}
