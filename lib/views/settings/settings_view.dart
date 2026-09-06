import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/zen_theme.dart';
import '../../models/ai_settings.dart';
import '../../providers/app_providers.dart';
import '../../providers/notebook_provider.dart';
import '../../providers/reminder_rule_provider.dart';
import '../../services/ai_service.dart';
import '../../services/local_data_service.dart';
import '../../services/startup_service.dart';
import '../../services/system_notification_service.dart';
import '../common/page_header.dart';

final aiSettingsProvider = NotifierProvider<AISettingsNotifier, AISettings>(
  AISettingsNotifier.new,
);

class AISettingsNotifier extends Notifier<AISettings> {
  @override
  AISettings build() => AIService.loadSettings();

  Future<void> save(AISettings settings) async {
    await AIService.saveSettings(settings);
    state = settings;
  }
}

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  late TextEditingController _baseUrlCtrl;
  late TextEditingController _apiKeyCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _dataDirectoryCtrl;
  late TextEditingController _backupPathCtrl;
  bool _obscureKey = true;
  String? _testResult;
  bool _testing = false;
  bool _exportingBackup = false;
  bool _previewingBackup = false;
  bool _importingBackup = false;
  bool _registeringNotifications = false;
  bool _startupEnabled = false;
  bool _savingStartup = false;
  bool _resetting = false;
  LocalBackupPreview? _backupPreview;
  late Future<NotificationHealth> _notificationHealth;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(aiSettingsProvider);
    _baseUrlCtrl = TextEditingController(text: settings.baseUrl);
    _apiKeyCtrl = TextEditingController(text: settings.apiKey);
    _modelCtrl = TextEditingController(text: settings.modelName);
    _dataDirectoryCtrl = TextEditingController();
    _backupPathCtrl = TextEditingController();
    _notificationHealth = SystemNotificationService.health();
    if (StartupService.supported) {
      _loadStartupState();
    }
    LocalDataService.documentsDirectory().then((directory) {
      if (!mounted) return;
      _dataDirectoryCtrl.text = directory.path;
    });
  }

  Future<void> _loadStartupState() async {
    try {
      final enabled = await StartupService.isEnabled();
      if (!mounted) return;
      setState(() => _startupEnabled = enabled);
    } catch (_) {
      // The startup entry is optional. A locked-down Windows policy should not
      // make the rest of Settings unusable.
    }
  }

  Future<void> _toggleStartup(bool enabled) async {
    if (_savingStartup) return;
    final previous = _startupEnabled;
    setState(() {
      _savingStartup = true;
      _startupEnabled = enabled;
    });
    try {
      await StartupService.setEnabled(enabled);
      if (!mounted) return;
      _showSnack(enabled ? '已设置登录 Windows 后自动启动到托盘' : '已关闭登录后自动启动');
    } catch (error) {
      if (!mounted) return;
      setState(() => _startupEnabled = previous);
      _showSnack('启动项设置失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _savingStartup = false);
    }
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _dataDirectoryCtrl.dispose();
    _backupPathCtrl.dispose();
    super.dispose();
  }

  AISettings _currentSettings({bool? enabled}) {
    return AISettings(
      baseUrl: _baseUrlCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      modelName: _modelCtrl.text.trim(),
      enabled: enabled ?? ref.read(aiSettingsProvider).enabled,
    );
  }

  Future<void> _save() async {
    final settings = _currentSettings();
    final autoEnable = settings.isConfigured && !settings.enabled;
    final toSave = autoEnable ? settings.copyWith(enabled: true) : settings;
    await ref.read(aiSettingsProvider.notifier).save(toSave);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(autoEnable ? '设置已保存，AI 已自动启用' : '设置已保存'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _testConnection() async {
    await _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final error = await AIService.testConnection(_currentSettings());
    if (!mounted) return;
    if (error == null) {
      await ref
          .read(aiSettingsProvider.notifier)
          .save(_currentSettings(enabled: true));
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = error ?? 'OK';
    });
  }

  void _applyPreset(AIPreset preset) {
    setState(() {
      _baseUrlCtrl.text = preset.baseUrl;
      _modelCtrl.text = preset.defaultModel;
    });
  }

  Future<void> _exportBackup() async {
    setState(() => _exportingBackup = true);
    try {
      final file = await LocalDataService.exportBackup();
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: '保存 ZenDiary 备份',
        fileName: file.uri.pathSegments.last,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: await file.readAsBytes(),
      );
      if (!mounted) return;
      if (destination == null) {
        _showSnack('已取消另存；本机备份已保留');
        return;
      }
      // Desktop returns a selected path; Android writes through its document provider.
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await file.copy(destination);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('备份已导出：$destination'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('备份失败：$e'),
          backgroundColor: ZenTheme.statusErrorStrong,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingBackup = false);
    }
  }

  Future<void> _chooseBackupFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择 ZenDiary 备份',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || !mounted) return;
      final path = result.files.single.path;
      if (path == null) {
        _showSnack('无法读取所选文件', isError: true);
        return;
      }
      setState(() {
        _backupPathCtrl.text = path;
        _backupPreview = null;
      });
      await _previewBackupFile();
    } catch (error) {
      if (mounted) _showSnack('选择文件失败：$error', isError: true);
    }
  }

  Future<void> _previewBackupFile() async {
    final path = _backupPathCtrl.text.trim();
    if (path.isEmpty) {
      _showSnack('请先填写备份 JSON 文件路径');
      return;
    }

    setState(() {
      _previewingBackup = true;
      _backupPreview = null;
    });
    try {
      final preview = await LocalDataService.previewBackupFile(path);
      if (!mounted) return;
      setState(() => _backupPreview = preview);
    } catch (e) {
      if (!mounted) return;
      _showSnack('预览失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _previewingBackup = false);
    }
  }

  Future<void> _importBackupFile() async {
    final preview = _backupPreview;
    if (preview == null) return;
    if (!preview.isZenDiaryBackup) {
      _showSnack('不是 ZenDiary 备份文件，不能导入', isError: true);
      return;
    }

    setState(() => _importingBackup = true);
    try {
      final result = await LocalDataService.importBackupFile(preview.filePath);
      ref.invalidate(allEntriesProvider);
      ref.invalidate(todoListProvider);
      ref.invalidate(notebookListProvider);
      ref.invalidate(reminderRuleProvider);
      ref.invalidate(aiSettingsProvider);
      final settings = AIService.loadSettings();
      _baseUrlCtrl.text = settings.baseUrl;
      _apiKeyCtrl.text = settings.apiKey;
      _modelCtrl.text = settings.modelName;
      if (!mounted) return;
      _showSnack('迁移完成：已导入 ${result.importedItems} 条数据');
    } catch (e) {
      if (!mounted) return;
      _showSnack('迁移失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _importingBackup = false);
    }
  }

  Future<void> _saveDataDirectory() async {
    final path = _dataDirectoryCtrl.text.trim();
    if (path.isEmpty) {
      _showSnack('请先填写数据目录路径', isError: true);
      return;
    }

    try {
      await LocalDataService.saveDataDirectoryPath(path);
      if (!mounted) return;
      _showSnack('数据目录已保存，重启 ZenDiary 后生效');
    } catch (e) {
      if (!mounted) return;
      _showSnack('保存数据目录失败：$e', isError: true);
    }
  }

  Future<void> _registerSystemNotifications() async {
    setState(() => _registeringNotifications = true);
    try {
      await SystemNotificationService.requestPermissions();
      await SystemNotificationService.showTestNotification();
      if (!mounted) return;
      setState(() {
        _notificationHealth = SystemNotificationService.health();
      });
      _showSnack('已发送测试通知，并刷新提醒健康状态');
    } catch (e) {
      if (!mounted) return;
      _showSnack('系统通知注册失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _registeringNotifications = false);
    }
  }

  Future<void> _confirmInitializeWorkspace() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZenTheme.backgroundCanvas,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: ZenTheme.statusError,
              size: 24,
            ),
            SizedBox(width: 10),
            Text('初始化新版工作区', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: const Text(
          '此操作将清空 ZenDiary 2.0 工作区中的随笔、待办、笔记和提醒规则，'
          '但不会删除旧版存储、设置或数据目录。\n\n'
          '此操作不可撤销，建议先导出备份。',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: ZenTheme.statusError,
              foregroundColor: ZenTheme.contentOnAccent,
            ),
            child: const Text('确认初始化新版工作区'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _initializeWorkspace();
    }
  }

  Future<void> _initializeWorkspace() async {
    setState(() => _resetting = true);
    try {
      await LocalDataService.clearV2Workspace();
      // 刷新所有 v2 内容 provider，让它们从空的 Hive box 重新读取。
      ref.invalidate(allEntriesProvider);
      ref.invalidate(todoListProvider);
      ref.invalidate(notebookListProvider);
      ref.invalidate(reminderRuleProvider);
      _testResult = null;
      if (!mounted) return;
      _showSnack('新版工作区已初始化；旧版存储和设置保持不变');
    } catch (e) {
      if (!mounted) return;
      _showSnack('初始化失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  void _showSnack(String text, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? ZenTheme.statusErrorStrong : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);

    return Column(
      children: [
        const PageHeader(title: '设置'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [
              _SectionHeader(
                title: '显示密度',
                trailing: SegmentedButton<UiDensity>(
                  segments: const [
                    ButtonSegment(
                      value: UiDensity.comfortable,
                      label: Text('舒适'),
                    ),
                    ButtonSegment(value: UiDensity.standard, label: Text('标准')),
                    ButtonSegment(value: UiDensity.compact, label: Text('紧凑')),
                  ],
                  selected: {ref.watch(uiDensityProvider)},
                  onSelectionChanged: (value) => ref
                      .read(uiDensityProvider.notifier)
                      .setDensity(value.first),
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: ZenTheme.accentMatcha,
                    selectedForegroundColor: ZenTheme.contentOnAccent,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '同时调整列表行高、按钮间距和页面留白；标准适合日常使用。',
                style: TextStyle(fontSize: 12, color: ZenTheme.textMuted),
              ),
              const SizedBox(height: 20),
              _SectionHeader(
                title: 'AI 助手',
                trailing: Switch(
                  value: settings.enabled,
                  activeThumbColor: ZenTheme.interactiveBrown,
                  onChanged: (value) {
                    ref
                        .read(aiSettingsProvider.notifier)
                        .save(_currentSettings(enabled: value));
                  },
                ),
              ),
              const SizedBox(height: 4),
              Text(
                settings.enabled && settings.isConfigured
                    ? 'AI 已启用：随笔会自动分析到时间线或待办'
                    : 'AI 未完整配置：明确日期、时间和任务仍会用本地规则整理，其余保存为随笔',
                style: TextStyle(fontSize: 12, color: ZenTheme.textMuted),
              ),
              const SizedBox(height: 24),
              const _SectionHeader(title: '服务商快速选择'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AIPreset.presets
                    .map(
                      (preset) => _PresetChip(
                        preset: preset,
                        isSelected: _baseUrlCtrl.text == preset.baseUrl,
                        onTap: () => _applyPreset(preset),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 24),
              const _SectionHeader(title: 'API 配置'),
              const SizedBox(height: 12),
              _ZenField(
                label: 'Base URL',
                controller: _baseUrlCtrl,
                hint: 'https://api.deepseek.com/v1',
                prefixIcon: Icons.link_outlined,
              ),
              const SizedBox(height: 12),
              _ZenField(
                label: 'API Key',
                controller: _apiKeyCtrl,
                hint: 'sk-xxxxxxxxxxxxxxxx',
                prefixIcon: Icons.key_outlined,
                obscureText: _obscureKey,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                  ),
                  tooltip: _obscureKey ? '显示密钥' : '隐藏密钥',
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
              const SizedBox(height: 12),
              _ZenField(
                label: '模型名称',
                controller: _modelCtrl,
                hint: 'deepseek-chat / qwen-turbo',
                prefixIcon: Icons.smart_toy_outlined,
              ),
              const SizedBox(height: 16),
              _ModelReference(),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: _testing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering_outlined, size: 16),
                      label: Text(_testing ? '测试中...' : '测试连接'),
                      onPressed: _testing ? null : _testConnection,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ZenTheme.interactiveBrown,
                        side: const BorderSide(
                          color: ZenTheme.interactiveBrown,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text('保存设置'),
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ZenTheme.interactiveBrown,
                        foregroundColor: ZenTheme.contentOnAccent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 16),
                _TestResultBanner(result: _testResult!),
              ],
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              _SectionHeader(
                title: '系统通知',
                trailing: OutlinedButton.icon(
                  icon: _registeringNotifications
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.notifications_active_outlined,
                          size: 16,
                        ),
                  label: Text(_registeringNotifications ? '注册中...' : '注册/测试通知'),
                  onPressed: _registeringNotifications
                      ? null
                      : _registerSystemNotifications,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZenTheme.interactiveBrown,
                    side: const BorderSide(color: ZenTheme.borderButton),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FutureBuilder<NotificationHealth>(
                future: _notificationHealth,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const LinearProgressIndicator(minHeight: 2);
                  }
                  final health = snapshot.data!;
                  final status = health.reliable
                      ? '可可靠准时提醒'
                      : health.windowsHasPackageIdentity
                      ? '不保证准时'
                      : '便携版：托盘运行时提醒';
                  final details = <String>[
                    status,
                    '待触发 ${health.pendingCount} 条',
                    if (!health.windowsHasPackageIdentity)
                      '关闭窗口会留在托盘，每 30 秒检查一次；支持临时稍后提醒；从托盘退出后不再提醒',
                    if (health.notificationsAllowed == false) '通知权限未允许',
                    if (health.exactAlarmsAllowed == false) '精确闹钟权限未允许',
                    if (health.error != null) '检查失败：${health.error}',
                  ];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: health.reliable
                          ? ZenTheme.statusSuccess.withValues(alpha: 0.08)
                          : ZenTheme.warningOrange.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          health.reliable
                              ? Icons.verified_outlined
                              : Icons.warning_amber_rounded,
                          color: health.reliable
                              ? ZenTheme.statusSuccessStrong
                              : ZenTheme.statusDeadlineStrong,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            details.join(' · '),
                            style: const TextStyle(fontSize: 12, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (StartupService.supported) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: ZenTheme.backgroundMuted,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ZenTheme.borderCard),
                  ),
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('登录 Windows 后启动到托盘'),
                    subtitle: const Text(
                      '便携版重启后仍可检查课程和待办提醒；从托盘完全退出后不会继续提醒。',
                      style: TextStyle(fontSize: 12, height: 1.35),
                    ),
                    value: _startupEnabled,
                    onChanged: _savingStartup ? null : _toggleStartup,
                    secondary: _savingStartup
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.rocket_launch_outlined),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              _SectionHeader(
                title: '本地数据与备份',
                trailing: OutlinedButton.icon(
                  icon: _exportingBackup
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined, size: 16),
                  label: Text(_exportingBackup ? '导出中...' : '导出备份'),
                  onPressed: _exportingBackup ? null : _exportBackup,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZenTheme.interactiveBrown,
                    side: const BorderSide(color: ZenTheme.borderButton),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LocalDataPanel(
                dataDirectoryController: _dataDirectoryCtrl,
                onSaveDataDirectory: _saveDataDirectory,
              ),
              const SizedBox(height: 12),
              const Text('数据保存在本机。电脑与手机不会自动同步，备份用于手动迁移。'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _previewingBackup || _importingBackup
                    ? null
                    : _chooseBackupFile,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('选择备份文件'),
              ),
              _BackupMigrationPanel(
                controller: _backupPathCtrl,
                preview: _backupPreview,
                isPreviewing: _previewingBackup,
                isImporting: _importingBackup,
                onPreview: _previewBackupFile,
                onImport: _importBackupFile,
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              _SectionHeader(
                title: '初始化',
                trailing: OutlinedButton.icon(
                  icon: _resetting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ZenTheme.statusError,
                          ),
                        )
                      : const Icon(
                          Icons.restart_alt_outlined,
                          size: 16,
                          color: ZenTheme.statusError,
                        ),
                  label: Text(
                    _resetting ? '初始化中...' : '初始化新版工作区',
                    style: const TextStyle(color: ZenTheme.statusError),
                  ),
                  onPressed: _resetting ? null : _confirmInitializeWorkspace,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZenTheme.statusError,
                    side: const BorderSide(color: ZenTheme.statusError),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '只清空新版工作区；旧版存储、设置和数据目录会保留。此操作不可撤销，建议先导出备份。',
                style: TextStyle(fontSize: 12, color: ZenTheme.statusError),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              const _SectionHeader(title: '关于 ZenDiary'),
              const SizedBox(height: 10),
              Text(
                '版本 0.1.0-dev',
                style: TextStyle(fontSize: 13, color: ZenTheme.textMuted),
              ),
              const SizedBox(height: 4),
              Text(
                '数据存储在本地 Documents 目录。',
                style: TextStyle(fontSize: 12, color: ZenTheme.textCompleted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocalDataPanel extends StatelessWidget {
  final TextEditingController dataDirectoryController;
  final VoidCallback onSaveDataDirectory;

  const _LocalDataPanel({
    required this.dataDirectoryController,
    required this.onSaveDataDirectory,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: LocalDataService.documentsDirectory(),
      builder: (context, snapshot) {
        final docsPath = snapshot.data?.path ?? '读取中...';
        final boxPaths = LocalDataService.boxPaths();

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ZenTheme.backgroundMuted,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ZenTheme.borderCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前生效目录',
                style: TextStyle(fontSize: 12, color: ZenTheme.textMuted),
              ),
              const SizedBox(height: 6),
              _DataPathRow(
                icon: Icons.folder_outlined,
                label: '数据目录',
                value: docsPath,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: dataDirectoryController,
                decoration: InputDecoration(
                  labelText: '手动设置数据目录',
                  hintText: r'E:\ZenDiaryData',
                  prefixIcon: Icon(
                    Icons.folder_open_outlined,
                    size: 18,
                    color: ZenTheme.textCompleted,
                  ),
                  filled: true,
                  fillColor: ZenTheme.backgroundCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: ZenTheme.borderCard),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: ZenTheme.borderCard),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: ZenTheme.interactiveBrown,
                    ),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('保存目录'),
                    onPressed: onSaveDataDirectory,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ZenTheme.interactiveBrown,
                      side: const BorderSide(color: ZenTheme.borderButton),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '新目录会在下次启动时用于保存 Hive 数据文件；迁移旧数据请先导出备份，再导入到新目录。',
                      style: TextStyle(fontSize: 12, color: ZenTheme.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...boxPaths.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DataPathRow(
                    icon: Icons.storage_outlined,
                    label: entry.key,
                    value: entry.value ?? '尚未创建文件',
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '备份会导出为 JSON 文件，保存在数据目录下的 zendiary_backups 文件夹。',
                style: TextStyle(fontSize: 12, color: ZenTheme.textMuted),
              ),
              const SizedBox(height: 4),
              Text(
                '安全提示：AI API Key 不会写入备份；导入时保留本机已有 Key。',
                style: TextStyle(fontSize: 12, color: ZenTheme.textMuted),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DataPathRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DataPathRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: ZenTheme.textMuted),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ZenTheme.interactiveBrown,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(fontSize: 12, color: ZenTheme.textMuted),
          ),
        ),
      ],
    );
  }
}

class _BackupMigrationPanel extends StatelessWidget {
  final TextEditingController controller;
  final LocalBackupPreview? preview;
  final bool isPreviewing;
  final bool isImporting;
  final VoidCallback onPreview;
  final VoidCallback onImport;

  const _BackupMigrationPanel({
    required this.controller,
    required this.preview,
    required this.isPreviewing,
    required this.isImporting,
    required this.onPreview,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final currentPreview = preview;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ZenTheme.backgroundCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ZenTheme.borderCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '迁移导入',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ZenTheme.interactiveBrown,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '填写 ZenDiary 备份 JSON 文件路径，先预览内容，再确认导入。导入会按 ID 合并数据，不会清空当前数据。',
            style: TextStyle(fontSize: 12, color: ZenTheme.textMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText:
                  r'Documents\zendiary_backups\zendiary_backup_....json',
              prefixIcon: Icon(
                Icons.description_outlined,
                size: 18,
                color: ZenTheme.textCompleted,
              ),
              filled: true,
              fillColor: ZenTheme.backgroundMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: ZenTheme.borderCard),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: ZenTheme.borderCard),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: ZenTheme.interactiveBrown),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                icon: isPreviewing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.visibility_outlined, size: 16),
                label: Text(isPreviewing ? '预览中...' : '预览文件'),
                onPressed: isPreviewing || isImporting ? null : onPreview,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ZenTheme.interactiveBrown,
                  side: const BorderSide(color: ZenTheme.borderButton),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                icon: isImporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ZenTheme.contentOnAccent,
                        ),
                      )
                    : const Icon(Icons.upload_file_outlined, size: 16),
                label: Text(isImporting ? '导入中...' : '确认迁移导入'),
                onPressed: currentPreview == null || isImporting || isPreviewing
                    ? null
                    : onImport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZenTheme.interactiveBrown,
                  foregroundColor: ZenTheme.contentOnAccent,
                ),
              ),
            ],
          ),
          if (currentPreview != null) ...[
            const SizedBox(height: 12),
            _BackupPreviewCard(preview: currentPreview),
          ],
        ],
      ),
    );
  }
}

class _BackupPreviewCard extends StatelessWidget {
  final LocalBackupPreview preview;

  const _BackupPreviewCard({required this.preview});

  @override
  Widget build(BuildContext context) {
    final exportedAt = preview.exportedAt == null
        ? '未知'
        : '${preview.exportedAt!.year}-${_two(preview.exportedAt!.month)}-${_two(preview.exportedAt!.day)} ${_two(preview.exportedAt!.hour)}:${_two(preview.exportedAt!.minute)}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: preview.isZenDiaryBackup
            ? ZenTheme.backgroundWarm
            : ZenTheme.statusOverdueBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: preview.isZenDiaryBackup
              ? ZenTheme.interactivePressed
              : ZenTheme.statusErrorBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                preview.isZenDiaryBackup
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                size: 18,
                color: preview.isZenDiaryBackup
                    ? ZenTheme.interactiveBrown
                    : ZenTheme.statusError,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preview.isZenDiaryBackup ? '可迁移的 ZenDiary 备份' : '无法识别的备份文件',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: preview.isZenDiaryBackup
                        ? ZenTheme.interactiveBrown
                        : ZenTheme.statusErrorStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PreviewRow(label: '文件', value: preview.fileName),
          _PreviewRow(label: '导出时间', value: exportedAt),
          _PreviewRow(label: '总条目', value: '${preview.totalItems}'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: preview.boxCounts.entries
                .map(
                  (entry) => Chip(
                    label: Text('${_boxLabel(entry.key)} ${entry.value}'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: ZenTheme.backgroundCard,
                    side: const BorderSide(color: ZenTheme.borderInputLegacy),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _boxLabel(String boxName) {
    return switch (boxName) {
      'diary_box_v2' => '随笔/时间线（新版）',
      'todo_box_v2' => '待办（新版）',
      'note_box_v2' => '笔记（新版）',
      'reminder_rule_box_v2' => '提醒（新版）',
      'settings_box' => '设置',
      _ => boxName,
    };
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;

  const _PreviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: ZenTheme.interactiveBrown,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(fontSize: 12, color: ZenTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: ZenTheme.interactiveBrown,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

class _ZenField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final bool obscureText;
  final Widget? suffixIcon;

  const _ZenField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.obscureText = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: ZenTheme.interactiveBrown,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: ZenTheme.textCompleted, fontSize: 13),
            prefixIcon: Icon(
              prefixIcon,
              size: 18,
              color: ZenTheme.textCompleted,
            ),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: ZenTheme.backgroundMuted,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: ZenTheme.borderCard),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: ZenTheme.borderCard),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: ZenTheme.interactiveBrown),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  final AIPreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: preset.hint,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? ZenTheme.interactiveBrown
                : ZenTheme.backgroundCard,
            border: Border.all(
              color: isSelected
                  ? ZenTheme.interactiveBrown
                  : ZenTheme.borderCard,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            preset.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isSelected
                  ? ZenTheme.contentOnAccent
                  : ZenTheme.textHeading,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelReference extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ZenTheme.backgroundWarm,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '推荐模型参考',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ZenTheme.interactiveBrown,
            ),
          ),
          SizedBox(height: 8),
          _ModelRow('DeepSeek', 'deepseek-chat', '适合分类和摘要'),
          _ModelRow('Qwen', 'qwen-turbo', '速度快，适合轻量使用'),
          _ModelRow('Qwen', 'qwen-plus', '质量更好'),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  final String vendor;
  final String model;
  final String desc;

  const _ModelRow(this.vendor, this.model, this.desc);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Wrap(
        spacing: 6,
        runSpacing: 3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: ZenTheme.interactivePressed,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              vendor,
              style: const TextStyle(
                fontSize: 10,
                color: ZenTheme.interactiveBrown,
              ),
            ),
          ),
          Text(
            model,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: ZenTheme.textHeading,
            ),
          ),
          Text(desc, style: TextStyle(fontSize: 11, color: ZenTheme.textMuted)),
        ],
      ),
    );
  }
}

class _TestResultBanner extends StatelessWidget {
  final String result;

  const _TestResultBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    final isOk = result == 'OK';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOk ? ZenTheme.statusSuccessLightBg : ZenTheme.statusOverdueBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOk
              ? ZenTheme.statusSuccessBorder
              : ZenTheme.statusErrorBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check_circle_outline : Icons.error_outline,
            size: 18,
            color: isOk ? ZenTheme.statusSuccess : ZenTheme.statusError,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isOk ? '连接成功，AI 已准备就绪' : result,
              style: TextStyle(
                fontSize: 13,
                color: isOk
                    ? ZenTheme.statusSuccessStrong
                    : ZenTheme.statusErrorStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
