import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cloud_account.dart';
import '../models/performance_settings.dart';

/// App settings state
class SettingsState {
  final ThemeMode themeMode;
  final List<String> rawExtensions;
  final List<String> jpgExtensions;
  final bool skipExistingFiles;
  final DuplicateHandling duplicateHandling;
  final CopyMode copyMode;
  final int maxParallelism;
  final List<R2Account> r2Accounts;
  final String? googleDriveCredentialsPath;

  const SettingsState({
    this.themeMode = ThemeMode.dark,
    this.rawExtensions = const [
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
    this.jpgExtensions = const ['jpg', 'jpeg'],
    this.skipExistingFiles = true,
    this.duplicateHandling = DuplicateHandling.skip,
    this.copyMode = CopyMode.ultraFast,
    this.maxParallelism = 4,
    this.r2Accounts = const [],
    this.googleDriveCredentialsPath,
  });

  List<String> get allExtensions => [...rawExtensions, ...jpgExtensions];

  SettingsState copyWith({
    ThemeMode? themeMode,
    List<String>? rawExtensions,
    List<String>? jpgExtensions,
    bool? skipExistingFiles,
    DuplicateHandling? duplicateHandling,
    CopyMode? copyMode,
    int? maxParallelism,
    List<R2Account>? r2Accounts,
    String? googleDriveCredentialsPath,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      rawExtensions: rawExtensions ?? this.rawExtensions,
      jpgExtensions: jpgExtensions ?? this.jpgExtensions,
      skipExistingFiles: skipExistingFiles ?? this.skipExistingFiles,
      duplicateHandling: duplicateHandling ?? this.duplicateHandling,
      copyMode: copyMode ?? this.copyMode,
      maxParallelism: maxParallelism ?? this.maxParallelism,
      r2Accounts: r2Accounts ?? this.r2Accounts,
      googleDriveCredentialsPath:
          googleDriveCredentialsPath ?? this.googleDriveCredentialsPath,
    );
  }
}

/// Settings state notifier with persistence
class SettingsNotifier extends StateNotifier<SettingsState> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  SettingsNotifier() : super(const SettingsState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('themeMode') ?? 'dark';
    final skip = prefs.getBool('skipExistingFiles') ?? true;
    final modeName = prefs.getString('copyMode') ?? 'ultraFast';
    final parallelism = prefs.getInt('maxParallelism') ?? 4;

    state = state.copyWith(
      themeMode: themeName == 'light' ? ThemeMode.light : ThemeMode.dark,
      skipExistingFiles: skip,
      copyMode: CopyMode.values.firstWhere(
        (e) => e.name == modeName,
        orElse: () => CopyMode.ultraFast,
      ),
      maxParallelism: parallelism,
    );

    // Load R2 accounts
    final accountsJson = prefs.getString('r2Accounts') ?? '[]';
    try {
      final list = jsonDecode(accountsJson) as List;
      final accounts = list
          .map((e) => R2Account.fromJson(e as Map<String, dynamic>))
          .toList();
      final hydrated = await _hydrateR2Accounts(accounts);
      state = state.copyWith(r2Accounts: hydrated);
      await _storeR2AccountsMetadata(prefs, hydrated);
    } catch (_) {}

    // Load GDrive credentials path
    final gdrivePath = prefs.getString('googleDriveCredentialsPath');
    if (gdrivePath != null) {
      state = state.copyWith(googleDriveCredentialsPath: gdrivePath);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'themeMode',
      state.themeMode == ThemeMode.light ? 'light' : 'dark',
    );
    await prefs.setBool('skipExistingFiles', state.skipExistingFiles);
    await prefs.setString('copyMode', state.copyMode.name);
    await prefs.setInt('maxParallelism', state.maxParallelism);
    await _storeR2AccountsMetadata(prefs, state.r2Accounts);
    if (state.googleDriveCredentialsPath != null) {
      await prefs.setString(
        'googleDriveCredentialsPath',
        state.googleDriveCredentialsPath!,
      );
    }
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _save();
  }

  void toggleTheme() {
    final newMode = state.themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    setThemeMode(newMode);
  }

  void setSkipExisting(bool value) {
    state = state.copyWith(skipExistingFiles: value);
    _save();
  }

  void setDuplicateHandling(DuplicateHandling handling) {
    state = state.copyWith(duplicateHandling: handling);
    _save();
  }

  void setCopyMode(CopyMode mode) {
    state = state.copyWith(copyMode: mode);
    _save();
  }

  void setMaxParallelism(int value) {
    state = state.copyWith(maxParallelism: value);
    _save();
  }

  // ── R2 Account Management ──

  void addR2Account(R2Account account) {
    final accounts = [...state.r2Accounts, account];
    state = state.copyWith(r2Accounts: accounts);
    _persistR2Secrets(account);
    _save();
  }

  void updateR2Account(R2Account account) {
    final accounts = state.r2Accounts
        .map((a) => a.id == account.id ? account : a)
        .toList();
    state = state.copyWith(r2Accounts: accounts);
    _persistR2Secrets(account);
    _save();
  }

  void removeR2Account(String accountId) {
    final accounts = state.r2Accounts.where((a) => a.id != accountId).toList();
    state = state.copyWith(r2Accounts: accounts);
    _deleteR2Secrets(accountId);
    _save();
  }

  void setGoogleDriveCredentialsPath(String path) {
    state = state.copyWith(googleDriveCredentialsPath: path);
    _save();
  }

  Future<List<R2Account>> _hydrateR2Accounts(List<R2Account> accounts) async {
    final hydrated = <R2Account>[];
    for (final account in accounts) {
      final accessKeyKey = _r2AccessKeyKey(account.id);
      final secretKeyKey = _r2SecretKeyKey(account.id);

      final storedAccess = await _secureStorage.read(key: accessKeyKey);
      final storedSecret = await _secureStorage.read(key: secretKeyKey);

      final accessKey = storedAccess ?? account.accessKey;
      final secretKey = storedSecret ?? account.secretKey;

      if (storedAccess == null && account.accessKey.isNotEmpty) {
        await _secureStorage.write(key: accessKeyKey, value: account.accessKey);
      }

      if (storedSecret == null && account.secretKey.isNotEmpty) {
        await _secureStorage.write(key: secretKeyKey, value: account.secretKey);
      }

      hydrated.add(
        R2Account(
          id: account.id,
          name: account.name,
          accountId: account.accountId,
          accessKey: accessKey,
          secretKey: secretKey,
          bucket: account.bucket,
          endpoint: account.endpoint,
          publicUrl: account.publicUrl,
        ),
      );
    }
    return hydrated;
  }

  Future<void> _storeR2AccountsMetadata(
    SharedPreferences prefs,
    List<R2Account> accounts,
  ) async {
    await prefs.setString(
      'r2Accounts',
      jsonEncode(accounts.map(_r2AccountToMetadata).toList()),
    );
  }

  Map<String, dynamic> _r2AccountToMetadata(R2Account account) {
    return {
      'id': account.id,
      'name': account.name,
      'accountId': account.accountId,
      'bucket': account.bucket,
      'endpoint': account.endpoint,
      'publicUrl': account.publicUrl,
    };
  }

  Future<void> _persistR2Secrets(R2Account account) async {
    await _secureStorage.write(
      key: _r2AccessKeyKey(account.id),
      value: account.accessKey,
    );
    await _secureStorage.write(
      key: _r2SecretKeyKey(account.id),
      value: account.secretKey,
    );
  }

  Future<void> _deleteR2Secrets(String accountId) async {
    await _secureStorage.delete(key: _r2AccessKeyKey(accountId));
    await _secureStorage.delete(key: _r2SecretKeyKey(accountId));
  }

  String _r2AccessKeyKey(String id) => 'r2_access_key_$id';
  String _r2SecretKeyKey(String id) => 'r2_secret_key_$id';
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) {
    return SettingsNotifier();
  },
);
