import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Firebase Storage boundary for product images. Firestore only ever receives
/// the resulting download URL.
class ProductPhotoService {
  ProductPhotoService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  Future<String> upload({
    required String productId,
    required Uint8List bytes,
    required String extension,
    void Function(double progress)? onProgress,
  }) async {
    final ext = extension.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    final safeExt =
        const {'jpg', 'jpeg', 'png', 'webp'}.contains(ext) ? ext : 'jpg';
    final ref = _storage.ref('products/$productId/product_image.$safeExt');
    final mime = safeExt == 'jpg' ? 'jpeg' : safeExt;
    final task =
        ref.putData(bytes, SettableMetadata(contentType: 'image/$mime'));
    task.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) {
        onProgress?.call(snapshot.bytesTransferred / snapshot.totalBytes);
      }
    });
    await task;
    return ref.getDownloadURL();
  }

  Future<void> deleteUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      await _storage.refFromURL(url).delete();
    } on FirebaseException catch (e) {
      // An old or already-deleted file must not prevent the Firestore update.
      if (e.code != 'object-not-found') rethrow;
    }
  }
}
