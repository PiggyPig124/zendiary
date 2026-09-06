import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zendiary/services/isolated_shared_preferences_store.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zendiary-prefs-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'persists values to the explicit directory across store instances',
    () async {
      final first = IsolatedSharedPreferencesStore(directory.path);
      expect(
        await first.setValue('String', 'flutter.trial', 'isolated'),
        isTrue,
      );
      expect(await first.setValue('Bool', 'flutter.enabled', true), isTrue);

      final second = IsolatedSharedPreferencesStore(directory.path);
      expect(await second.getAll(), {
        'flutter.trial': 'isolated',
        'flutter.enabled': true,
      });
      expect(
        File(
          '${directory.path}${Platform.pathSeparator}shared_preferences.json',
        ).existsSync(),
        isTrue,
      );
    },
  );

  test('clear honors the same prefix and leaves other keys intact', () async {
    final store = IsolatedSharedPreferencesStore(directory.path);
    await store.setValue('String', 'flutter.keep', 'yes');
    await store.setValue('String', 'other.keep', 'yes');

    await store.clear();

    expect(await store.getAllWithPrefix('flutter.'), isEmpty);
    expect(await store.getAllWithPrefix('other.'), {'other.keep': 'yes'});
  });
}
