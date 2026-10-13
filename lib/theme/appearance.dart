import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Where the appearance choice is kept between launches.
abstract class AppearancePersistence {
  Future<String?> read();
  Future<void> write(String value);
}

/// A one-line file in the app support directory. Not the keychain: a theme
/// choice is not a secret, and keychain items outlive an uninstall on iOS.
class FileAppearancePersistence implements AppearancePersistence {
  Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/appearance');

  @override
  Future<String?> read() async {
    final File file = await _file();
    return await file.exists() ? (await file.readAsString()).trim() : null;
  }

  @override
  Future<void> write(String value) async {
    final File file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }
}

class MemoryAppearancePersistence implements AppearancePersistence {
  MemoryAppearancePersistence([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

/// The user's light / dark / system choice (Settings > Appearance).
///
/// One process-wide instance ([sharedAppearance]) so the demo session, which
/// runs in its own provider container, follows the same choice as the app.
class Appearance extends ChangeNotifier {
  Appearance(this._persistence);

  final AppearancePersistence _persistence;
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// Reads the saved choice. A missing or unreadable value keeps `system`.
  Future<void> load() async {
    try {
      final ThemeMode? saved = _parse(await _persistence.read());
      if (saved != null && saved != _mode) {
        _mode = saved;
        notifyListeners();
      }
    } on Object {
      // A broken preference file must never block app start.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      await _persistence.write(mode.name);
    } on Object {
      // The choice still applies for this session.
    }
  }

  static ThemeMode? _parse(String? value) {
    for (final ThemeMode mode in ThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }
}

final Appearance sharedAppearance = Appearance(FileAppearancePersistence());

final Provider<Appearance> appearanceProvider = Provider<Appearance>(
  (Ref ref) => sharedAppearance,
);
