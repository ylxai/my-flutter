import 'dart:io';

/// Copy mode enum
enum CopyMode { standard, highPerformance, ultraFast }

/// Optimization level
enum OptimizationLevel { balanced, speed, memory, maximum }

/// Hash algorithm for verification
enum HashAlgorithmType { none, md5, sha256 }

/// Duplicate file handling strategy
enum DuplicateHandling { overwrite, skip, rename }

/// Performance settings configuration
class PerformanceSettings {
  final CopyMode mode;
  final OptimizationLevel optimization;
  final int maxParallelism;
  final int bufferSize;
  final bool useMemoryMapping;
  final bool useDirectIO;
  final bool preAllocateFiles;
  final bool flushToDisk;

  const PerformanceSettings({
    this.mode = CopyMode.ultraFast,
    this.optimization = OptimizationLevel.speed,
    this.maxParallelism = 4,
    this.bufferSize = 1048576,
    this.useMemoryMapping = true,
    this.useDirectIO = true,
    this.preAllocateFiles = true,
    this.flushToDisk = true,
  });

  /// Auto-configure based on system capabilities
  factory PerformanceSettings.autoConfigure() {
    final cpuCount = Platform.numberOfProcessors;
    int parallelism;
    int buffer;

    if (cpuCount >= 8) {
      parallelism = cpuCount * 3;
      buffer = 2 * 1024 * 1024; // 2MB
    } else if (cpuCount >= 4) {
      parallelism = cpuCount * 2;
      buffer = 1024 * 1024; // 1MB
    } else {
      parallelism = cpuCount;
      buffer = 512 * 1024; // 512KB
    }

    return PerformanceSettings(maxParallelism: parallelism, bufferSize: buffer);
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'optimization': optimization.name,
    'maxParallelism': maxParallelism,
    'bufferSize': bufferSize,
    'useMemoryMapping': useMemoryMapping,
    'useDirectIO': useDirectIO,
    'preAllocateFiles': preAllocateFiles,
    'flushToDisk': flushToDisk,
  };

  factory PerformanceSettings.fromJson(Map<String, dynamic> json) {
    return PerformanceSettings(
      mode: CopyMode.values.firstWhere(
        (e) => e.name == json['mode'],
        orElse: () => CopyMode.ultraFast,
      ),
      optimization: OptimizationLevel.values.firstWhere(
        (e) => e.name == json['optimization'],
        orElse: () => OptimizationLevel.speed,
      ),
      maxParallelism: json['maxParallelism'] as int? ?? 4,
      bufferSize: json['bufferSize'] as int? ?? 1048576,
      useMemoryMapping: json['useMemoryMapping'] as bool? ?? true,
      useDirectIO: json['useDirectIO'] as bool? ?? true,
      preAllocateFiles: json['preAllocateFiles'] as bool? ?? true,
      flushToDisk: json['flushToDisk'] as bool? ?? true,
    );
  }
}
