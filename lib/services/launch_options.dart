/// Command-line options that must be applied before any persistent service is
/// initialized.
///
/// The Windows trial launcher passes `--data-dir` together with isolated
/// APPDATA/LOCALAPPDATA values. Keeping the parser independent from Flutter
/// makes it safe to exercise without opening a window or touching a database.
class LaunchOptions {
  static const String dataDirectoryFlag = '--data-dir';

  const LaunchOptions._();

  /// Returns the explicit data directory from [args], if supplied.
  ///
  /// Both `--data-dir=path` and `--data-dir path` are accepted. A malformed
  /// option throws instead of silently falling back to the user's profile,
  /// which is especially important for an isolated trial process.
  static String? dataDirectoryFromArgs(Iterable<String> args) {
    final values = args.toList(growable: false);
    String? result;
    for (var index = 0; index < values.length; index++) {
      final argument = values[index].trim();
      String? candidate;
      if (argument == dataDirectoryFlag) {
        if (index + 1 >= values.length ||
            values[index + 1].trim().isEmpty ||
            values[index + 1].trim().startsWith('--')) {
          throw const FormatException('使用 --data-dir 时必须提供非空目录路径');
        }
        candidate = values[++index].trim();
      } else if (argument.startsWith('$dataDirectoryFlag=')) {
        candidate = argument.substring(dataDirectoryFlag.length + 1).trim();
        if (candidate.isEmpty) {
          throw const FormatException('使用 --data-dir= 时必须提供非空目录路径');
        }
      } else {
        continue;
      }

      if (result != null && result != candidate) {
        throw const FormatException('不能同时指定多个不同的 --data-dir');
      }
      result = candidate;
    }
    return result;
  }
}
