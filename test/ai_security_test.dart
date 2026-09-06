import 'package:flutter_test/flutter_test.dart';
import 'package:zendiary/models/ai_settings.dart';
import 'package:zendiary/services/ai_service.dart';
import 'package:zendiary/services/mcp_service.dart';

void main() {
  AISettings settings(String baseUrl) => AISettings(
    baseUrl: baseUrl,
    apiKey: 'synthetic-test-key',
    modelName: 'synthetic-model',
  );

  test('AI endpoints require TLS except for explicit loopback hosts', () {
    expect(settings('https://provider.example/v1').isConfigured, isTrue);
    expect(settings('http://localhost:8080/v1').isConfigured, isTrue);
    expect(settings('http://127.0.0.1:8080/v1').isConfigured, isTrue);
    expect(settings('http://[::1]:8080/v1').isConfigured, isTrue);

    final remoteHttp = settings('http://provider.example/v1');
    expect(remoteHttp.isConfigured, isFalse);
    expect(remoteHttp.endpointError, contains('HTTPS'));
  });

  test('AI endpoints reject unsupported schemes and embedded secrets', () {
    for (final value in [
      'ftp://provider.example/v1',
      'https://user:password@provider.example/v1',
      'https://provider.example/v1?token=query-token',
      'https://provider.example/v1#fragment',
    ]) {
      expect(settings(value).isConfigured, isFalse, reason: value);
    }
  });

  test(
    'connection check rejects unsafe endpoints before network access',
    () async {
      final error = await AIService.testConnection(
        settings('http://provider.example/v1'),
      );
      expect(error, contains('HTTPS'));
    },
  );

  test('legacy MCP entry stays disabled', () async {
    expect(McpService.isEnabled, isFalse);
    await McpService.startServer(port: 12345);
    McpService.stopServer();
  });
}
