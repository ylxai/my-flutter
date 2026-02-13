import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/copy_profile.dart';

/// Service for managing copy profiles (load/save/delete)
class ProfileService {
  final Future<String> _profilesFolderFuture;

  ProfileService() : _profilesFolderFuture = _getProfilesFolder();

  static Future<String> _getProfilesFolder() async {
    final appDir = await getApplicationSupportDirectory();
    final folder = p.join(appDir.path, 'profiles');
    await Directory(folder).create(recursive: true);
    return folder;
  }

  Future<String> _profilesFile() async {
    final folder = await _profilesFolderFuture;
    return p.join(folder, 'profiles.json');
  }

  /// Get all saved profiles
  Future<List<CopyProfile>> getAllProfiles() async {
    final file = File(await _profilesFile());
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
    final path = await _profilesFile();
    final file = File(path);
    final json = jsonEncode(profiles.map((p) => p.toJson()).toList());
    final tempFile = File('$path.tmp');
    await tempFile.writeAsString(json);
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(path);
  }
}
