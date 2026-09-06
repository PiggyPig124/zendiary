import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/system_notification_service.dart';
import 'app_providers.dart';
import 'reminder_rule_provider.dart';

/// Refreshes notification health when source items change, so Today can warn
/// only while there is an actual reminder that may be affected.
final notificationHealthProvider = FutureProvider<NotificationHealth>((ref) {
  ref.watch(reminderRuleProvider);
  ref.watch(todoListProvider);
  ref.watch(allEntriesProvider);
  return SystemNotificationService.health();
});
