import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zendiary/core/database/db_service.dart';
import 'package:zendiary/services/launch_options.dart';

void main() {
  test('data-dir accepts separated and equals forms', () {
    expect(
      LaunchOptions.dataDirectoryFromArgs([
        '--background',
        '--data-dir',
        r'C:\trial data',
      ]),
      r'C:\trial data',
    );
    expect(
      LaunchOptions.dataDirectoryFromArgs([r'--data-dir=C:\trial-data']),
      r'C:\trial-data',
    );
  });

  test('malformed data-dir does not silently fall back', () {
    expect(
      () => LaunchOptions.dataDirectoryFromArgs(['--data-dir']),
      throwsFormatException,
    );
    expect(
      () => LaunchOptions.dataDirectoryFromArgs(['--data-dir=']),
      throwsFormatException,
    );
    expect(
      () => LaunchOptions.dataDirectoryFromArgs([
        '--data-dir',
        r'C:\one',
        '--data-dir',
        r'C:\two',
      ]),
      throwsFormatException,
    );
  });

  test(
    'explicit data directory wins before SharedPreferences is read',
    () async {
      SharedPreferences.setMockInitialValues({
        DBService.dataDirectoryPreferenceKey: r'C:\user-profile',
      });
      DBService.configureDataDirectoryOverride(r'C:\trial-profile');
      try {
        final resolved = await DBService.resolveDataDirectory();
        expect(resolved.path, Directory(r'C:\trial-profile').absolute.path);
      } finally {
        DBService.debugClearDataDirectoryOverride();
      }
    },
  );
}
