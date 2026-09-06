import 'dart:io';

import 'package:flutter/foundation.dart';

/// Controls the optional per-user Windows startup entry used by the portable
/// build. Keeping this separate from the notification scheduler makes the
/// reminder behavior explicit: startup keeps the tray process alive after a
/// reboot, while the user can still exit it at any time.
abstract class StartupAdapter {
  Future<bool> isEnabled(String executablePath);

  Future<void> setEnabled(String executablePath, bool enabled);
}

class _WindowsRegistryStartupAdapter implements StartupAdapter {
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'ZenDiary';

  @override
  Future<bool> isEnabled(String executablePath) async {
    final result = await Process.run(
      'reg.exe',
      ['query', _runKey, '/v', _valueName],
      runInShell: true,
    );
    if (result.exitCode != 0) return false;
    // Treat an entry pointing at an old copied executable as disabled. The
    // next explicit enable action replaces it with the current build path.
    final registeredPath = result.stdout.toString().toLowerCase();
    return registeredPath.contains(executablePath.toLowerCase());
  }

  @override
  Future<void> setEnabled(String executablePath, bool enabled) async {
    final result = enabled
        ? await Process.run(
            'reg.exe',
            [
              'add',
              _runKey,
              '/v',
              _valueName,
              '/t',
              'REG_SZ',
              '/d',
              '"$executablePath" ${StartupService.backgroundArgument}',
              '/f',
            ],
            runInShell: true,
          )
        : await Process.run(
            'reg.exe',
            ['delete', _runKey, '/v', _valueName, '/f'],
            runInShell: true,
          );
    if (result.exitCode != 0) {
      final detail = result.stderr.toString().trim();
      throw StateError(
        detail.isEmpty ? 'Windows 启动项操作失败' : detail,
      );
    }
  }
}

class StartupService {
  static const backgroundArgument = '--background';
  static StartupAdapter _adapter = _WindowsRegistryStartupAdapter();
  static bool? _supportedOverride;

  static bool get supported => _supportedOverride ?? Platform.isWindows;

  static String get executablePath => Platform.resolvedExecutable;

  static bool hasBackgroundArgument(Iterable<String> args) => args.any(
        (argument) =>
            argument.trim().toLowerCase() == backgroundArgument,
      );

  static Future<bool> isEnabled() async {
    if (!supported) return false;
    return _adapter.isEnabled(executablePath);
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!supported) return;
    await _adapter.setEnabled(executablePath, enabled);
  }

  @visibleForTesting
  static void debugUseAdapter(StartupAdapter adapter, {bool supported = true}) {
    _adapter = adapter;
    _supportedOverride = supported;
  }

  @visibleForTesting
  static void debugReset() {
    _adapter = _WindowsRegistryStartupAdapter();
    _supportedOverride = null;
  }
}
