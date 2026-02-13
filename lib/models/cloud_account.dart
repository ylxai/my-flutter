// Cloud account model for R2 and upload configuration.
//
// Stores credentials and configuration for Cloudflare R2
// multi-account support.

/// Cloudflare R2 account configuration
class R2Account {
  final String id;
  final String name;
  final String accountId;
  final String accessKey;
  final String secretKey;
  final String bucket;
  final String endpoint;
  final String publicUrl;

  const R2Account({
    required this.id,
    required this.name,
    required this.accountId,
    required this.accessKey,
    required this.secretKey,
    required this.bucket,
    this.endpoint = '',
    this.publicUrl = '',
  });

  /// Auto-generate endpoint from accountId
  String get resolvedEndpoint {
    if (endpoint.isNotEmpty) return endpoint;
    return 'https://$accountId.r2.cloudflarestorage.com';
  }

  /// Auto-generate public URL
  String get resolvedPublicUrl {
    if (publicUrl.isNotEmpty) return publicUrl;
    return 'https://$bucket.$accountId.r2.dev';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'accountId': accountId,
    'accessKey': accessKey,
    'secretKey': secretKey,
    'bucket': bucket,
    'endpoint': endpoint,
    'publicUrl': publicUrl,
  };

  factory R2Account.fromJson(Map<String, dynamic> json) {
    return R2Account(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      accountId: json['accountId'] as String? ?? '',
      accessKey: json['accessKey'] as String? ?? '',
      secretKey: json['secretKey'] as String? ?? '',
      bucket: json['bucket'] as String? ?? '',
      endpoint: json['endpoint'] as String? ?? '',
      publicUrl: json['publicUrl'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is R2Account && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Upload configuration for a publish session
class UploadConfig {
  final String eventName;
  final String sourceFolder;
  final R2Account? r2Account;
  final bool uploadOriginalToDrive;
  final String? googleDriveCredentialsPath;
  final bool recursiveScan;
  final List<String> extensions;
  final int thumbWidth;
  final int previewWidth;
  final int thumbQuality;
  final int previewQuality;

  const UploadConfig({
    required this.eventName,
    required this.sourceFolder,
    this.r2Account,
    this.uploadOriginalToDrive = false,
    this.googleDriveCredentialsPath,
    this.recursiveScan = true,
    this.extensions = const [
      'jpg',
      'jpeg',
      'png',
      'cr2',
      'cr3',
      'nef',
      'arw',
      'raf',
      'orf',
      'rw2',
      'dng',
      'raw',
      'pef',
      'srw',
    ],
    this.thumbWidth = 400,
    this.previewWidth = 1920,
    this.thumbQuality = 80,
    this.previewQuality = 85,
  });
}

/// Gallery manifest — uploaded to R2 as index
class GalleryManifest {
  final String eventName;
  final DateTime createdAt;
  final int totalPhotos;
  final List<GalleryPhoto> photos;
  final String? driveFolderId;

  const GalleryManifest({
    required this.eventName,
    required this.createdAt,
    required this.totalPhotos,
    required this.photos,
    this.driveFolderId,
  });

  Map<String, dynamic> toJson() => {
    'eventName': eventName,
    'createdAt': createdAt.toIso8601String(),
    'totalPhotos': totalPhotos,
    'photos': photos.map((p) => p.toJson()).toList(),
    if (driveFolderId != null) 'driveFolderId': driveFolderId,
  };
}

/// Single photo entry in gallery manifest
class GalleryPhoto {
  final String name;
  final String thumbKey;
  final String previewKey;

  const GalleryPhoto({
    required this.name,
    required this.thumbKey,
    required this.previewKey,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'thumb': thumbKey,
    'preview': previewKey,
  };
}
