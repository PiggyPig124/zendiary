class AISettings {
  final String baseUrl;
  final String apiKey;
  final String modelName;
  final bool enabled;

  const AISettings({
    this.baseUrl = '',
    this.apiKey = '',
    this.modelName = '',
    this.enabled = false,
  });

  /// Returns null only for an endpoint that is safe to contact from the app.
  ///
  /// Remote providers must use TLS. Plain HTTP remains available for an
  /// explicitly local compatibility server so a student can keep using a
  /// self-hosted endpoint without making an accidental network downgrade.
  String? get endpointError {
    final value = baseUrl.trim();
    if (value.isEmpty) return '请填写 Base URL';
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Base URL 必须是有效的 HTTPS 地址，或明确的本机 HTTP 地址';
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') {
      return 'Base URL 只支持 HTTPS，或本机 HTTP 地址';
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      return 'Base URL 不能包含账号、密码、查询参数或片段';
    }
    final host = uri.host.toLowerCase();
    final localHost =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    if (scheme == 'http' && !localHost) {
      return '远程 AI 服务必须使用 HTTPS；HTTP 仅允许 localhost、127.0.0.1 或 ::1';
    }
    return null;
  }

  bool get isConfigured =>
      apiKey.trim().isNotEmpty &&
      modelName.trim().isNotEmpty &&
      endpointError == null;

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'modelName': modelName,
    'enabled': enabled,
  };

  factory AISettings.fromJson(Map<dynamic, dynamic> json) => AISettings(
    baseUrl: json['baseUrl']?.toString() ?? '',
    apiKey: json['apiKey']?.toString() ?? '',
    modelName: json['modelName']?.toString() ?? '',
    enabled: json['enabled'] == true,
  );

  AISettings copyWith({
    String? baseUrl,
    String? apiKey,
    String? modelName,
    bool? enabled,
  }) => AISettings(
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    modelName: modelName ?? this.modelName,
    enabled: enabled ?? this.enabled,
  );
}

class AIPreset {
  final String name;
  final String baseUrl;
  final String defaultModel;
  final String hint;

  const AIPreset({
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    required this.hint,
  });

  static const List<AIPreset> presets = [
    AIPreset(
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      defaultModel: 'deepseek-chat',
      hint: '适合日记分类和摘要，成本较低。',
    ),
    AIPreset(
      name: '阿里云 Qwen',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      defaultModel: 'qwen-turbo',
      hint: '可使用 qwen-turbo / qwen-plus / qwen-max。',
    ),
    AIPreset(
      name: '自定义',
      baseUrl: '',
      defaultModel: '',
      hint: '任何兼容 /chat/completions 的服务。',
    ),
  ];
}
