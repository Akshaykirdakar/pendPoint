// Photo checks done before an upload (the same limits as storage.rules),
// and the Storage path behind a download URL (so replacing a product photo
// never deletes the file just uploaded).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:pend_point/services/photo_check.dart';

Uint8List _bytes(List<int> head, [int size = 64]) =>
    Uint8List.fromList([...head, ...List.filled(size - head.length, 0)]);

void main() {
  final jpg = _bytes([0xFF, 0xD8, 0xFF, 0xE0]);
  final png = _bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final webp = _bytes([0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x45, 0x42, 0x50]);

  test('the real type comes from the file, not its name', () {
    expect(photoTypeOf(jpg), 'jpg');
    expect(photoTypeOf(png), 'png');
    expect(photoTypeOf(webp), 'webp');
    expect(photoTypeOf(_bytes([0x25, 0x50, 0x44, 0x46])), isNull); // PDF
    expect(photoTypeOf(Uint8List(0)), isNull);
  });

  test('only JPG/PNG/WEBP under 5 MB may be uploaded', () {
    expect(photoProblem(jpg), isNull);
    expect(photoProblem(png), isNull);
    expect(photoProblem(webp), isNull);
    expect(photoProblem(_bytes([0x25, 0x50, 0x44, 0x46])), contains('JPG'));
    expect(photoProblem(Uint8List(0)), isNotNull);
    expect(photoProblem(_bytes([0xFF, 0xD8, 0xFF], maxPhotoBytes - 1)), isNull);
    expect(photoProblem(_bytes([0xFF, 0xD8, 0xFF], maxPhotoBytes)),
        contains('5 MB'));
  });

  test('Storage path of a download URL', () {
    const a = 'https://firebasestorage.googleapis.com/v0/b/x.appspot.com/o/'
        'stores%2FSTORE001%2Fproducts%2Fp1%2Fproduct_image.jpg?alt=media&token=1';
    const b = 'https://firebasestorage.googleapis.com/v0/b/x.appspot.com/o/'
        'stores%2FSTORE001%2Fproducts%2Fp1%2Fproduct_image.jpg?alt=media&token=2';
    const legacy = 'https://firebasestorage.googleapis.com/v0/b/x.appspot.com/o/'
        'products%2Fp1%2Fproduct_image.jpg?alt=media&token=1';
    expect(storagePathOfUrl(a), 'stores/STORE001/products/p1/product_image.jpg');
    // Same file, new token: the old one must NOT be deleted.
    expect(storagePathOfUrl(a), storagePathOfUrl(b));
    expect(storagePathOfUrl(legacy), isNot(storagePathOfUrl(a)));
    expect(storagePathOfUrl('not a url'), isNull);
  });
}
