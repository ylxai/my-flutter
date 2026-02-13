import 'dart:convert';
import 'dart:io';

import '../models/copy_profile.dart';

/// Service for managing copy profiles (load/save/delete)
class ProfileService {
  final String _profilesFolder;

  ProfileService()
      : _profilesFolder = _getProfilesFolder();

  static String _getProfilesFolder() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final folder = '$home/.filecopy_utility/profiles';
    Directory(folder).createSync(recursive: true);
    return folder;
  }

  String get _profilesFile => '$_profilesFolder/profiles.json';

  /// Get all saved profiles
  Future<List<CopyProfile>> getAllProfiles() async {
    final file = File(_profilesFile);
    if (!file.existsSync()) return [];

    try {
      final json = await file.readAsString();
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => CopyProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Get a specific profile by name
  Future<CopyProfile?> getProfile(String name) async {
    final profiles = await getAllProfiles();
    try {
      return profiles.firstWhere((p) => p.name == name);
    } catch (_) {
      return null;
    }
  }

  /// Save a profile
  Future<void> saveProfile(CopyProfile profile) async {
    final profiles = await getAllProfiles();
    final index = profiles.indexWhere((p) => p.name == profile.name);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }

    await _writeProfiles(profiles);
  }

  /// Delete a profile
  Future<void> deleteProfile(String name) async {
    final profiles = await getAllProfiles();
    profiles.removeWhere((p) => p.name == name);
    await _writeProfiles(profiles);
  }

  Future<void> _writeProfiles(List<CopyProfile> profiles) async {
    final file = File(_profilesFile);
    final json = jsonEncode(profiles.map((p) => p.toJson()).toList());
    await file.writeAsString(json);
  }
}
