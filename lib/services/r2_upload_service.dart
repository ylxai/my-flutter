// R2 upload service for Cloudflare R2 (S3-compatible).
//
// Handles uploading thumbnail and preview images to R2 buckets
// using S3-compatible API via the minio package.

import 'dart:convert';
import 'dart:io';

import 'package:minio/minio.dart';

import '../models/cloud_account.dart';

/// Service for uploading files to Cloudflare R2
class R2UploadService {
  Minio? _client;
  R2Account? _account;

  /// Initialize with an R2 account
  void configure(R2Account account) {
    _account = account;
    final endpoint = _normalizeEndpoint(account.resolvedEndpoint);
    _client = Minio(
      endPoint: endpoint.host,
      accessKey: account.accessKey,
      secretKey: account.secretKey,
      useSSL: endpoint.scheme != 'http',
      port: endpoint.hasPort
          ? endpoint.port
          : (endpoint.scheme == 'http' ? 80 : 443),
    );
  }

  /// Check if the service is configured
  bool get isConfigured => _client != null && _account != null;

  /// Test connection by checking if bucket exists
  Future<bool> testConnection() async {
    if (!isConfigured) return false;
    try {
      final exists = await _client!.bucketExists(_account!.bucket);
      return exists;
    } catch (e) {
      return false;
    }
  }

  /// Upload a file to R2
  ///
  /// [filePath] — local file path
  /// [objectKey] — key in R2 bucket (e.g. "event-name/thumbs/photo.webp")
  /// Returns the public URL of the uploaded object
  Future<String> uploadFile({
    required String filePath,
    required String objectKey,
    String? contentType,
  }) async {
    _ensureConfigured();

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final stream = file.openRead();
    final size = await file.length();

    await _client!.putObject(
      _account!.bucket,
      objectKey,
      Stream.castFrom(stream),
      size: size,
      metadata: _buildMetadata(contentType),
    );

    // Return public URL
    final baseUrl = _account!.resolvedPublicUrl.replaceAll(RegExp(r'/$'), '');
    return '$baseUrl/$objectKey';
  }

  /// Upload a JSON manifest to R2
  Future<String> uploadManifest({
    required String objectKey,
    required Map<String, dynamic> manifest,
  }) async {
    _ensureConfigured();

    final jsonStr = const JsonEncoder.withIndent('  ').convert(manifest);
    final bytes = utf8.encode(jsonStr);

    await _client!.putObject(
      _account!.bucket,
      objectKey,
      Stream.value(bytes),
      size: bytes.length,
      metadata: _buildMetadata('application/json'),
    );

    final baseUrl = _account!.resolvedPublicUrl.replaceAll(RegExp(r'/$'), '');
    return '$baseUrl/$objectKey';
  }

  /// List objects in a prefix (for checking existing uploads)
  Future<List<String>> listObjects(String prefix) async {
    _ensureConfigured();

    final objects = <String>[];
    final stream = _client!.listObjects(_account!.bucket, prefix: prefix);

    await for (final chunk in stream) {
      for (final obj in chunk.objects) {
        if (obj.key != null) objects.add(obj.key!);
      }
    }

    return objects;
  }

  // ── Private ──

  void _ensureConfigured() {
    if (!isConfigured) {
      throw Exception(
        'R2UploadService not configured. Call configure() first.',
      );
    }
  }

  Uri _normalizeEndpoint(String url) {
    final uri = Uri.parse(url);
    if (uri.scheme.isEmpty) {
      return Uri.parse('https://$url');
    }
    return uri;
  }

  Map<String, String>? _buildMetadata(String? contentType) {
    if (contentType == null || contentType.isEmpty) {
      return null;
    }
    return {'Content-Type': contentType};
  }
}
