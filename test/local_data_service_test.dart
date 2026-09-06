import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zendiary/services/local_data_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:zendiary/core/database/db_service.dart';
import 'package:zendiary/models/ai_settings.dart';

void main() {
  test('backup sanitization never exports an AI API key', () {
    final safe = LocalDataService.sanitizeAiSettingsForBackup({
      'baseUrl': 'https://example.invalid/v1',
      'modelName': 'student-model',
      'enabled': true,
      'apiKey': 'sk-secret-value',
    });

    expect(safe.containsKey('apiKey'), isFalse);
    expect(safe['apiKeyConfigured'], isTrue);
    expect(safe['baseUrl'], 'https://example.invalid/v1');
  });

  test('backup import preserves the complete local AI configuration', () {
    final imported = LocalDataService.mergeImportedAiSettings(
      {
        'baseUrl': 'https://example.invalid/v1',
        'apiKey': 'old-secret-in-backup',
        'apiKeyConfigured': true,
      },
      existingSettings: const AISettings(
        baseUrl: 'https://device.example/v1',
        apiKey: 'current-device-key',
        modelName: 'device-model',
        enabled: true,
      ),
    );

    expect(imported, {
      'baseUrl': 'https://device.example/v1',
      'apiKey': 'current-device-key',
      'modelName': 'device-model',
      'enabled': true,
    });
    expect(imported.containsKey('apiKeyConfigured'), isFalse);

    final freshDevice = LocalDataService.mergeImportedAiSettings({
      'apiKeyConfigured': true,
    });
    expect(freshDevice.containsKey('apiKey'), isFalse);
    expect(freshDevice['enabled'], isFalse);
  });

  test(
    'backup sanitization strips credentials and query tokens from Base URL',
    () {
      final safe = LocalDataService.sanitizeAiSettingsForBackup({
        'baseUrl':
            'https://url-user:url-pass@example.invalid/v1?api_key=query-token#fragment',
        'apiKey': 'stored-key',
      });

      expect(safe['baseUrl'], 'https://example.invalid/v1');
      expect(safe.toString(), isNot(contains('url-pass')));
      expect(safe.toString(), isNot(contains('query-token')));

      final imported = LocalDataService.mergeImportedAiSettings(
        safe,
        existingSettings: const AISettings(
          baseUrl: 'https://device.example/v1',
          apiKey: 'device-key',
          modelName: 'device-model',
        ),
      );
      expect(imported['baseUrl'], 'https://device.example/v1');
      expect(imported['apiKey'], 'device-key');
    },
  );

  test('backup import cannot replace the local AI endpoint or key', () async {
    final directory = await Directory.systemTemp.createTemp(
      'zendiary-backup-security-',
    );
    Hive.init(directory.path);
    for (final name in LocalDataService.boxNames) {
      await Hive.openBox(name);
    }
    addTearDown(() async {
      await Hive.close();
      if (directory.existsSync()) await directory.delete(recursive: true);
    });

    final settingsBox = Hive.box(DBService.settingsBoxName);
    await settingsBox.put('ai_settings', {
      'baseUrl': 'https://trusted.example/v1',
      'apiKey': 'local-device-key',
      'modelName': 'trusted-model',
      'enabled': true,
    });

    final backup = File(
      '${directory.path}${Platform.pathSeparator}import.json',
    );
    await backup.writeAsString(
      jsonEncode({
        'app': 'ZenDiary',
        'boxes': {
          DBService.settingsBoxName: {
            'ai_settings': {
              'baseUrl': 'https://attacker.example/v1',
              'apiKey': 'backup-key',
              'modelName': 'attacker-model',
              'enabled': true,
            },
          },
        },
      }),
    );

    await LocalDataService.importBackupFile(backup.path);

    expect(settingsBox.get('ai_settings'), {
      'baseUrl': 'https://trusted.example/v1',
      'apiKey': 'local-device-key',
      'modelName': 'trusted-model',
      'enabled': true,
    });
  });
}
