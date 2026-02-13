// Publish history provider — persisted list of published galleries.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Record of a published gallery
class PublishRecord {
  final String id;
  final String eventName;
  final DateTime publishedAt;
  final int photoCount;
  final int successCount;
  final int failedCount;
  final Duration duration;
  final String galleryUrl;
  final String? driveFolderId;
  final bool isSuccess;

  const PublishRecord({
    required this.id,
    required this.eventName,
    required this.publishedAt,
    required this.photoCount,
    required this.successCount,
    required this.failedCount,
    required this.duration,
    required this.galleryUrl,
    this.driveFolderId,
    required this.isSuccess,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'eventName': eventName,
        'publishedAt': publishedAt.toIso8601String(),
        'photoCount': photoCount,
        'successCount': successCount,
        'failedCount': failedCount,
        'durationMs': duration.inMilliseconds,
        'galleryUrl': galleryUrl,
        'driveFolderId': driveFolderId,
        'isSuccess': isSuccess,
      };

  factory PublishRecord.fromJson(Map<String, dynamic> json) {
    return PublishRecord(
      id: json['id'] as String? ?? '',
      eventName: json['eventName'] as String? ?? '',
      publishedAt: DateTime.tryParse(
            json['publishedAt'] as String? ?? '',
          ) ??
          DateTime.now(),
      photoCount: json['photoCount'] as int? ?? 0,
      successCount: json['successCount'] as int? ?? 0,
      failedCount: json['failedCount'] as int? ?? 0,
      duration: Duration(
        milliseconds: json['durationMs'] as int? ?? 0,
      ),
      galleryUrl: json['galleryUrl'] as String? ?? '',
      driveFolderId: json['driveFolderId'] as String?,
      isSuccess: json['isSuccess'] as bool? ?? false,
    );
  }
}

/// Publish history state notifier
class PublishHistoryNotifier
    extends StateNotifier<List<PublishRecord>> {
  PublishHistoryNotifier() : super([]) {
    _load();
  }

  static const _key = 'publish_history';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? '[]';
    try {
      final list = jsonDecode(raw) as List;
      state = list
          .map((e) =>
              PublishRecord.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) =>
            b.publishedAt.compareTo(a.publishedAt));
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(state.map((r) => r.toJson()).toList()),
    );
  }

  void addRecord(PublishRecord record) {
    state = [record, ...state];
    _save();
  }

  void removeRecord(String id) {
    state = state.where((r) => r.id != id).toList();
    _save();
  }

  void clearAll() {
    state = [];
    _save();
  }
}

final publishHistoryProvider = StateNotifierProvider<
    PublishHistoryNotifier, List<PublishRecord>>((ref) {
  return PublishHistoryNotifier();
});
