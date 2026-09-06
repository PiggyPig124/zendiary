/// Compatibility shim for the old in-process MCP server.
///
/// The app no longer exposes a localhost HTTP endpoint. Keeping the method
/// shape lets older startup code compile while making accidental calls safe;
/// integrations must use an explicit, authenticated provider path instead.
class McpService {
  static bool get isEnabled => false;

  static Future<void> startServer({int port = 12345}) async {
    // Intentionally no-op. The legacy server was unauthenticated and is
    // disabled even if a stale caller still invokes this method.
  }

  static void stopServer() {
    // Kept as a no-op for callers compiled against the old API.
  }
}
