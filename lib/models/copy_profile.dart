import 'performance_settings.dart';

/// Copy profile — saved configuration for copy operations
class CopyProfile {
  String name;
  String description;
  String sourceListPath;
  String destinationFolder;
  int threadCount;
  bool verifyIntegrity;
  HashAlgorithmType hashAlgorithm;
  bool autoRetry;
  int maxRetries;
  bool overwriteExisting;
  DuplicateHandling duplicateHandling;
  DateTime createdDate;
  DateTime? lastUsed;

  CopyProfile({
    this.name = '',
    this.description = '',
    this.sourceListPath = '',
    this.destinationFolder = '',
    this.threadCount = 4,
    this.verifyIntegrity = false,
    this.hashAlgorithm = HashAlgorithmType.none,
    this.autoRetry = false,
    this.maxRetries = 3,
    this.overwriteExisting = true,
    this.duplicateHandling = DuplicateHandling.overwrite,
    DateTime? createdDate,
    this.lastUsed,
  }) : createdDate = createdDate ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'sourceListPath': sourceListPath,
        'destinationFolder': destinationFolder,
        'threadCount': threadCount,
        'verifyIntegrity': verifyIntegrity,
        'hashAlgorithm': hashAlgorithm.name,
        'autoRetry': autoRetry,
        'maxRetries': maxRetries,
        'overwriteExisting': overwriteExisting,
        'duplicateHandling': duplicateHandling.name,
        'createdDate': createdDate.toIso8601String(),
        'lastUsed': lastUsed?.toIso8601String(),
      };

  factory CopyProfile.fromJson(Map<String, dynamic> json) {
    return CopyProfile(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      sourceListPath: json['sourceListPath'] as String? ?? '',
      destinationFolder: json['destinationFolder'] as String? ?? '',
      threadCount: json['threadCount'] as int? ?? 4,
      verifyIntegrity: json['verifyIntegrity'] as bool? ?? false,
      hashAlgorithm: HashAlgorithmType.values.firstWhere(
        (e) => e.name == json['hashAlgorithm'],
        orElse: () => HashAlgorithmType.none,
      ),
      autoRetry: json['autoRetry'] as bool? ?? false,
      maxRetries: json['maxRetries'] as int? ?? 3,
      overwriteExisting: json['overwriteExisting'] as bool? ?? true,
      duplicateHandling: DuplicateHandling.values.firstWhere(
        (e) => e.name == json['duplicateHandling'],
        orElse: () => DuplicateHandling.overwrite,
      ),
      createdDate: json['createdDate'] != null
          ? DateTime.parse(json['createdDate'] as String)
          : DateTime.now(),
      lastUsed: json['lastUsed'] != null
          ? DateTime.parse(json['lastUsed'] as String)
          : null,
    );
  }

  @override
  String toString() => name;
}
