// Google Drive upload service.
//
// Handles OAuth2 authentication and uploading original files
// to Google Drive as the secondary storage provider.

import 'dart:convert';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for uploading files to Google Drive
class GoogleDriveUploadService {
  static const _scopes = [drive.DriveApi.driveFileScope];

  AutoRefreshingAuthClient? _authClient;
  drive.DriveApi? _driveApi;

  /// Whether the service is authenticated
  bool get isAuthenticated => _driveApi != null;

  /// Authenticate using OAuth2 with credentials.json
  ///
  /// [credentialsPath] — path to credentials.json file
  /// Opens browser for consent if needed.
  Future<void> authenticate(String credentialsPath) async {
    final file = File(credentialsPath);
    if (!await file.exists()) {
      throw Exception('credentials.json not found at $credentialsPath');
    }

    final jsonStr = await file.readAsString();
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    final installed = json['installed'] as Map<String, dynamic>;

    final clientId = ClientId(
      installed['client_id'] as String,
      installed['client_secret'] as String,
    );

    _authClient = await clientViaUserConsent(clientId, _scopes, (
      String url,
    ) async {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        throw Exception(
          'Cannot open browser for OAuth consent. Please open: $url',
        );
      }
    });

    _driveApi = drive.DriveApi(_authClient!);
  }

  /// Create a folder in Google Drive root
  /// Returns the folder ID
  Future<String> createFolder(String name) async {
    _ensureAuthenticated();

    // Check if folder already exists
    final existing = await findFolder(name);
    if (existing != null) return existing;

    final folder = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder';

    final result = await _driveApi!.files.create(folder);
    final id = result.id;
    if (id == null || id.isEmpty) {
      throw Exception('Drive API returned empty folder id');
    }
    return id;
  }

  /// Find a folder by name
  /// Returns folder ID if found, null otherwise
  Future<String?> findFolder(String name) async {
    _ensureAuthenticated();

    final query =
        "name='$name' and "
        "mimeType='application/vnd.google-apps.folder' and "
        "trashed=false";

    final result = await _driveApi!.files.list(
      q: query,
      spaces: 'drive',
      $fields: 'files(id, name)',
    );

    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id;
    }
    return null;
  }

  /// Upload a file to a specific folder
  ///
  /// Returns the file ID
  Future<String> uploadFile({
    required String filePath,
    required String folderId,
    String? fileName,
  }) async {
    _ensureAuthenticated();

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final name = fileName ?? filePath.split(Platform.pathSeparator).last;

    final driveFile = drive.File()
      ..name = name
      ..parents = [folderId];

    final media = drive.Media(file.openRead(), await file.length());

    final result = await _driveApi!.files.create(driveFile, uploadMedia: media);

    final id = result.id;
    if (id == null || id.isEmpty) {
      throw Exception('Drive API returned empty file id');
    }
    return id;
  }

  /// Make a folder publicly readable
  Future<void> makeFolderPublic(String folderId) async {
    _ensureAuthenticated();

    final permission = drive.Permission()
      ..type = 'anyone'
      ..role = 'reader';

    await _driveApi!.permissions.create(permission, folderId);
  }

  /// Dispose of authentication resources
  void dispose() {
    _authClient?.close();
    _authClient = null;
    _driveApi = null;
  }

  // ── Private ──

  void _ensureAuthenticated() {
    if (!isAuthenticated) {
      throw Exception('Not authenticated. Call authenticate() first.');
    }
  }
}
