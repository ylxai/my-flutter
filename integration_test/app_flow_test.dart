import 'dart:collection';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:filecopy_utility/app.dart';
import 'package:filecopy_utility/models/cloud_account.dart';
import 'package:filecopy_utility/models/performance_settings.dart';
import 'package:filecopy_utility/providers/copy_provider.dart';
import 'package:filecopy_utility/providers/settings_provider.dart';
import 'package:filecopy_utility/providers/upload_provider.dart';
import 'package:filecopy_utility/services/file_picker_adapter.dart';
import 'package:filecopy_utility/services/google_drive_upload_service.dart';
import 'package:filecopy_utility/services/r2_upload_service.dart';
import 'package:filecopy_utility/services/upload_orchestrator.dart';
import 'package:filecopy_utility/screens/main_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Copy flow + UI buttons', (tester) async {
    final tempDir = await Directory.systemTemp.createTemp('e2e_copy');
    final sourceDir = Directory(p.join(tempDir.path, 'source'));
    await sourceDir.create(recursive: true);

    await File(p.join(sourceDir.path, 'photo1.jpg')).writeAsBytes([1, 2, 3]);
    await File(p.join(sourceDir.path, 'photo2.jpg')).writeAsBytes([4, 5, 6]);

    final listFile = File(p.join(tempDir.path, 'list.txt'));
    await listFile.writeAsString('photo1\nphoto2\n');

    final filePicker = FakeFilePickerAdapter(
      directoryQueue: Queue.of([sourceDir.path]),
      fileQueue: Queue.of([
        FilePickerResult([
          PlatformFile(
            name: p.basename(listFile.path),
            size: await listFile.length(),
            path: listFile.path,
          ),
        ]),
      ]),
    );

    final settings = SettingsNotifier(
      initialState: const SettingsState(
        r2Accounts: [
          R2Account(
            id: 'test',
            name: 'Test Account',
            accountId: 'acct',
            accessKey: 'ak',
            secretKey: 'sk',
            bucket: 'test-bucket',
          ),
        ],
      ),
      loadFromPrefs: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filePickerProvider.overrideWithValue(filePicker),
          settingsProvider.overrideWith((ref) => settings),
          r2ServiceProvider.overrideWithValue(FakeR2UploadService()),
          driveServiceProvider.overrideWithValue(FakeDriveUploadService()),
          uploadOrchestratorFactoryProvider.overrideWithValue(
            ({required r2Service, required driveService}) =>
                FakeUploadOrchestrator(
                  r2Service: r2Service,
                  driveService: driveService,
                ),
          ),
        ],
        child: const FileCopyApp(),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.photo_library_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.content_copy_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'photo1\nphoto2');
    await tester.pumpAndSettle();

    await Clipboard.setData(const ClipboardData(text: 'photo1\nphoto2'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Validate'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MainScreen)),
    );
    expect(container.read(copyProvider).validFiles.length, 2);

    await tester.tap(find.text('START COPY'));
    await _pumpUntil(
      tester,
      condition: () {
        final status = container.read(copyProvider).status;
        return status != CopyStatus.copying &&
            status != CopyStatus.validating &&
            status != CopyStatus.paused;
      },
      timeout: const Duration(seconds: 20),
    );
    final finalStatus = container.read(copyProvider).status;
    expect([CopyStatus.completed, CopyStatus.idle].contains(finalStatus), true);

    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Publish flow with mocked services + buttons', (tester) async {
    final tempDir = await Directory.systemTemp.createTemp('e2e_publish');
    final sourceDir = Directory(p.join(tempDir.path, 'source'));
    await sourceDir.create(recursive: true);

    await File(p.join(sourceDir.path, 'photo1.jpg')).writeAsBytes([1, 2, 3]);
    await File(p.join(sourceDir.path, 'photo2.jpg')).writeAsBytes([4, 5, 6]);

    final filePicker = FakeFilePickerAdapter(
      directoryQueue: Queue.of([sourceDir.path]),
      fileQueue: Queue<FilePickerResult?>(),
    );

    final settings = SettingsNotifier(
      initialState: const SettingsState(
        r2Accounts: [
          R2Account(
            id: 'test',
            name: 'Test Account',
            accountId: 'acct',
            accessKey: 'ak',
            secretKey: 'sk',
            bucket: 'test-bucket',
          ),
        ],
      ),
      loadFromPrefs: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filePickerProvider.overrideWithValue(filePicker),
          settingsProvider.overrideWith((ref) => settings),
          r2ServiceProvider.overrideWithValue(FakeR2UploadService()),
          driveServiceProvider.overrideWithValue(FakeDriveUploadService()),
          uploadOrchestratorFactoryProvider.overrideWithValue(
            ({required r2Service, required driveService}) =>
                FakeUploadOrchestrator(
                  r2Service: r2Service,
                  driveService: driveService,
                ),
          ),
        ],
        child: const FileCopyApp(),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.cloud_upload_rounded));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Test Event');

    await tester.tap(find.text('Select folder...'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<R2Account>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test Account (test-bucket)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upload originals to Google Drive'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Publish Gallery'));
    await _pumpUntil(
      tester,
      condition: () => find.text('Gallery Published!').evaluate().isNotEmpty,
    );

    expect(find.text('Gallery Published!'), findsOneWidget);

    await tester.tap(find.text('Publish Another'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.cloud_upload_rounded));
    await tester.pumpAndSettle();
  });

  testWidgets('Navigation + settings buttons', (tester) async {
    final settings = SettingsNotifier(
      initialState: const SettingsState(),
      loadFromPrefs: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith((ref) => settings)],
        child: const FileCopyApp(),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.photo_library_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Gallery'), findsWidgets);

    await tester.tap(find.byIcon(Icons.cloud_upload_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.schedule_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('coming soon'), findsWidgets);

    await tester.tap(find.byIcon(Icons.bar_chart_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('coming soon'), findsWidgets);

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<DuplicateHandling>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(DuplicateHandling.values.first.name).last);
    await tester.pumpAndSettle();

    final sliderFinder = find.byType(Slider);
    if (sliderFinder.evaluate().isNotEmpty) {
      await tester.ensureVisible(sliderFinder.first);
      await tester.drag(
        sliderFinder.first,
        const Offset(60, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
    }

    final addButton = find.byIcon(Icons.add_circle);
    if (addButton.evaluate().isNotEmpty) {
      await tester.ensureVisible(addButton.first);
      await tester.tap(addButton.first);
      await tester.pumpAndSettle();
      expect(find.text('Add R2 Account'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }

    final deleteButtons = find.byIcon(Icons.delete_outline);
    if (deleteButtons.evaluate().isNotEmpty) {
      await tester.ensureVisible(deleteButtons.first);
      await tester.tap(deleteButtons.first);
      await tester.pumpAndSettle();
    }
  });
}

class FakeFilePickerAdapter implements FilePickerAdapter {
  final Queue<String?> directoryQueue;
  final Queue<FilePickerResult?> fileQueue;

  FakeFilePickerAdapter({
    required this.directoryQueue,
    required this.fileQueue,
  });

  @override
  Future<String?> getDirectoryPath({String? dialogTitle}) async {
    if (directoryQueue.isEmpty) return null;
    return directoryQueue.removeFirst();
  }

  @override
  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    if (fileQueue.isEmpty) return null;
    return fileQueue.removeFirst();
  }
}

class FakeR2UploadService extends R2UploadService {
  @override
  void configure(R2Account account) {}

  @override
  Future<bool> testConnection() async => true;

  @override
  Future<String> uploadFile({
    required String filePath,
    required String objectKey,
    String? contentType,
  }) async {
    return 'https://example.invalid/$objectKey';
  }

  @override
  Future<String> uploadManifest({
    required String objectKey,
    required Map<String, dynamic> manifest,
  }) async {
    return 'https://example.invalid/$objectKey';
  }
}

class FakeDriveUploadService extends GoogleDriveUploadService {
  @override
  bool get isAuthenticated => true;

  @override
  Future<void> authenticate(String credentialsPath) async {}

  @override
  Future<String> createFolder(String name) async => 'drive-folder';

  @override
  Future<String> uploadFile({
    required String filePath,
    required String folderId,
    String? fileName,
  }) async {
    return 'drive-file';
  }

  @override
  Future<void> makeFolderPublic(String folderId) async {}
}

class FakeUploadOrchestrator extends UploadOrchestrator {
  FakeUploadOrchestrator({
    required super.r2Service,
    required super.driveService,
  });

  @override
  Stream<UploadProgress> execute(UploadConfig config) async* {
    yield const UploadProgress(
      phase: UploadPhase.scanning,
      message: 'Scanning source folder...',
      overallProgress: 0.05,
    );
    await Future.delayed(const Duration(milliseconds: 50));

    yield const UploadProgress(
      phase: UploadPhase.processing,
      message: 'Processing images (resize + WebP)...',
      overallProgress: 0.2,
    );
    await Future.delayed(const Duration(milliseconds: 50));

    yield const UploadProgress(
      phase: UploadPhase.uploadingToR2,
      message: 'Uploading to R2...',
      overallProgress: 0.6,
    );
    await Future.delayed(const Duration(milliseconds: 50));

    if (config.uploadOriginalToDrive) {
      yield const UploadProgress(
        phase: UploadPhase.uploadingToDrive,
        message: 'Uploading to Drive...',
        overallProgress: 0.8,
      );
      await Future.delayed(const Duration(milliseconds: 50));
    }

    yield const UploadProgress(
      phase: UploadPhase.generatingManifest,
      message: 'Generating manifest...',
      overallProgress: 0.95,
    );
    await Future.delayed(const Duration(milliseconds: 50));

    yield const UploadProgress(
      phase: UploadPhase.completed,
      message: 'Upload complete!',
      overallProgress: 1.0,
      galleryUrl: 'https://example.invalid/manifest.json',
      totalFiles: 2,
      currentFile: 2,
      successCount: 2,
    );
  }
}

Future<void> _pumpUntil(
  WidgetTester tester, {
  required bool Function() condition,
  Duration timeout = const Duration(seconds: 5),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (condition()) return;
  }
  throw TestFailure('Condition not met within ${timeout.inSeconds}s');
}
