import 'package:flutter_test/flutter_test.dart';
import 'package:zendiary/services/system_notification_service.dart';

void main() {
  test('notification health explains missing Android notification permission', () {
    const health = NotificationHealth(
      initialized: true,
      notificationsAllowed: false,
      exactAlarmsAllowed: true,
      windowsHasPackageIdentity: true,
      pendingCount: 1,
    );

    expect(health.needsAction, isTrue);
    expect(health.actionMessage, contains('通知权限'));
  });

  test('notification health explains missing exact alarm permission', () {
    const health = NotificationHealth(
      initialized: true,
      notificationsAllowed: true,
      exactAlarmsAllowed: false,
      windowsHasPackageIdentity: true,
      pendingCount: 1,
    );

    expect(health.needsAction, isTrue);
    expect(health.actionMessage, contains('精确闹钟'));
  });

  test('portable health does not require Android permission action', () {
    const health = NotificationHealth(
      initialized: true,
      notificationsAllowed: null,
      exactAlarmsAllowed: null,
      windowsHasPackageIdentity: false,
      pendingCount: 0,
    );

    expect(health.needsAction, isFalse);
  });
}
