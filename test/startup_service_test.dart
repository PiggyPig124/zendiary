import 'package:flutter_test/flutter_test.dart';
import 'package:zendiary/services/startup_service.dart';

class _FakeStartupAdapter implements StartupAdapter {
  bool enabled = false;
  int reads = 0;
  int writes = 0;
  String? lastPath;

  @override
  Future<bool> isEnabled(String executablePath) async {
    reads++;
    lastPath = executablePath;
    return enabled;
  }

  @override
  Future<void> setEnabled(String executablePath, bool value) async {
    writes++;
    lastPath = executablePath;
    enabled = value;
  }
}

void main() {
  tearDown(StartupService.debugReset);

  test('startup service delegates state to the platform adapter', () async {
    final adapter = _FakeStartupAdapter();
    StartupService.debugUseAdapter(adapter);

    expect(await StartupService.isEnabled(), isFalse);
    await StartupService.setEnabled(true);
    expect(await StartupService.isEnabled(), isTrue);
    await StartupService.setEnabled(false);

    expect(adapter.reads, 2);
    expect(adapter.writes, 2);
    expect(adapter.lastPath, StartupService.executablePath);
    expect(adapter.enabled, isFalse);
  });

  test('unsupported startup service does not touch the adapter', () async {
    final adapter = _FakeStartupAdapter();
    StartupService.debugUseAdapter(adapter, supported: false);

    expect(await StartupService.isEnabled(), isFalse);
    await StartupService.setEnabled(true);

    expect(adapter.reads, 0);
    expect(adapter.writes, 0);
  });

  test('startup argument is case-insensitive and ignores unrelated arguments', () {
    expect(
      StartupService.hasBackgroundArgument(const ['--verbose', '--BACKGROUND']),
      isTrue,
    );
    expect(
      StartupService.hasBackgroundArgument(const ['--background=true']),
      isFalse,
    );
  });
}
