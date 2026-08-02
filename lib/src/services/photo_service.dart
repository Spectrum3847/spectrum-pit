import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'http_timeout_client.dart';

enum PhotoSource { camera, gallery, file }

class PickedPhoto {
  const PickedPhoto({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

class PhotoException implements Exception {
  const PhotoException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PhotoService {
  PhotoService({
    required Future<String?> Function() idToken,
    Uri? baseUrl,
    http.Client? httpClient,
    Future<PickedPhoto?> Function(PhotoSource source)? picker,
    int cacheLimit = _defaultCacheLimit,
  }) : _idToken = idToken,
       _baseUrl = baseUrl ?? Uri.parse(_defaultBaseUrl),

       _client =
           httpClient ?? TimeoutHttpClient(timeout: const Duration(minutes: 1)),
       _picker = picker ?? _defaultPicker,
       _cacheLimit = cacheLimit;

  static const String _defaultBaseUrl =
      'https://spectrumpit-photos.spectrum-3847.workers.dev';

  static const int maxBytes = 2 * 1024 * 1024;

  static const int _defaultCacheLimit = 12;

  static const double _maxEdge = 1600;
  static const int _jpegQuality = 80;

  final Future<String?> Function() _idToken;
  final Uri _baseUrl;
  final http.Client _client;
  final Future<PickedPhoto?> Function(PhotoSource source) _picker;
  final int _cacheLimit;

  final LinkedHashMap<String, Uint8List> _cache =
      LinkedHashMap<String, Uint8List>();

  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  List<PhotoSource> get sources => _isMobile
      ? const [PhotoSource.camera, PhotoSource.gallery]
      : const [PhotoSource.file];

  Future<String?> capture(PhotoSource source) async {
    final picked = await _picker(source);
    if (picked == null) return null;
    return upload(picked);
  }

  Future<PickedPhoto?> pickImage() =>
      _picker(_isMobile ? PhotoSource.gallery : PhotoSource.file);

  Future<String> upload(PickedPhoto photo) async {
    if (photo.bytes.isEmpty) {
      throw const PhotoException('That image file is empty.');
    }
    if (photo.bytes.length > maxBytes) {
      throw PhotoException(
        'That image is ${_megabytes(photo.bytes.length)}, over the 2 MB limit. '
        'Resize it, or take the photo in the app so it downscales.',
      );
    }
    final response = await _send(
      http.Request('POST', _baseUrl.resolve('/photos'))
        ..headers['Content-Type'] = photo.contentType
        ..bodyBytes = photo.bytes,
    );
    if (response == null) throw _signedOut;
    if (response.statusCode != 201) throw _failure('upload', response);
    final key = (jsonDecode(response.body) as Map<String, dynamic>)['key'];
    if (key is! String || key.isEmpty) {
      throw const PhotoException('Storage did not return a photo id.');
    }
    _remember(key, photo.bytes);
    return key;
  }

  Future<Uint8List?> fetch(String key) async {
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final response = await _send(
      http.Request('GET', _baseUrl.resolve('/photos/$key')),
    );
    if (response == null) return null;
    if (response.statusCode != 200) throw _failure('load', response);
    final bytes = response.bodyBytes;
    _remember(key, bytes);
    return bytes;
  }

  Future<void> delete(String key) async {
    _cache.remove(key);
    final response = await _send(
      http.Request('DELETE', _baseUrl.resolve('/photos/$key')),
    );
    if (response == null) throw _signedOut;
    if (response.statusCode != 204 && response.statusCode != 404) {
      throw _failure('remove', response);
    }
  }

  void close() => _client.close();

  Future<http.Response?> _send(http.Request request) async {
    final token = await _idToken();
    if (token == null || token.isEmpty) return null;
    request.headers['Authorization'] = 'Bearer $token';
    return http.Response.fromStream(await _client.send(request));
  }

  static const PhotoException _signedOut = PhotoException(
    'Sign in with your team account to use photos.',
  );

  PhotoException _failure(String verb, http.Response response) {
    return switch (response.statusCode) {
      403 => const PhotoException(
        'Storage refused the request. Your account may not have a team role '
        'yet.',
      ),
      404 => const PhotoException('That photo is no longer in storage.'),
      413 => const PhotoException('That image is over the 2 MB limit.'),
      415 => const PhotoException('That file is not an image we can store.'),
      _ => PhotoException(
        'Could not $verb the photo (storage returned ${response.statusCode}).',
      ),
    };
  }

  void _remember(String key, Uint8List bytes) {
    _cache.remove(key);
    _cache[key] = bytes;
    while (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
  }

  static String _megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  static Future<PickedPhoto?> _defaultPicker(PhotoSource source) =>
      _isMobile ? _pickFromDevice(source) : _pickFile();

  static Future<PickedPhoto?> _pickFromDevice(PhotoSource source) async {
    final file = await ImagePicker().pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: _maxEdge,
      maxHeight: _maxEdge,
      imageQuality: _jpegQuality,
    );
    if (file == null) return null;
    return PickedPhoto(
      bytes: await file.readAsBytes(),
      contentType: _contentTypeOf(file.name),
    );
  }

  static Future<PickedPhoto?> _pickFile() async {
    const typeGroup = XTypeGroup(
      label: 'images',
      extensions: ['png', 'jpg', 'jpeg', 'webp', 'heic'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return null;
    return PickedPhoto(
      bytes: await file.readAsBytes(),
      contentType: _contentTypeOf(file.name),
    );
  }

  static String _contentTypeOf(String name) {
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' || 'heif' => 'image/heic',
      _ => 'image/jpeg',
    };
  }
}
