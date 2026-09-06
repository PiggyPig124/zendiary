import 'package:flutter/material.dart';

class ZenTheme {
  // ═══════════════════════════════════════════════════════════════════════════
  // Zen Color Palette (保留原有名称，新增语义化令牌)
  // ═══════════════════════════════════════════════════════════════════════════

  // ── 原有基础色（保持向后兼容）──
  static const Color riceWhite = Color(0xFFFDFCF8);
  static const Color oatmeal = Color(0xFFEAE6DF);
  static const Color lightGrey = Color(0xFFF2F2F2);
  static const Color textPrimary = Color(0xFF2C2C2C);
  static const Color textSecondary = Color(0xFF7A7A7A);
  static const Color accent = Color(0xFF8B9A8B); // A muted matcha green
  static const Color warningOrange = Color(0xFFD69A70);

  // ── 背景系 ──
  static const Color backgroundCanvas = riceWhite;
  static const Color backgroundWarm = Color(0xFFF5F2ED);
  static const Color backgroundCard = Colors.white;
  static const Color backgroundToday = Color(0xFFFFF8ED);
  static const Color backgroundMuted = Color(0xFFF9F7F4);
  static const Color backgroundPale = Color(0xFFFBFDFA);
  static const Color surfaceWarm = Color(0xFFF0EDE8);

  // ── 边框系 ──
  static const Color borderCard = Color(0xFFEDE8E3);
  static const Color borderSubtle = Color(0xFFE8E1D8);
  static const Color borderWarm = Color(0xFFE4DED5);
  static const Color borderButton = Color(0xFFE0D8CF);
  static const Color borderSage = Color(0xFFDFE6DC);

  // ── 文字系 ──
  static const Color textHeading = Color(0xFF3D3327);
  static const Color textBody = textPrimary;
  static const Color textMuted = Color(0xFF9E8B77);
  static const Color textCompleted = Color(0xFFB0A89B);
  static const Color textWeekend = Color(0xFFC4A497);

  // ── 交互 / 强调色 ──
  static const Color interactiveBrown = Color(0xFF6B5B47); // 保留向后兼容，已弃用为主交互色
  static const Color interactivePrimary = Color(
    0xFF8B9A8B,
  ); // 新的主交互色 → accentMatcha
  static const Color interactivePressed = Color(0xFFE8E8E0); // 调整为更偏绿的按压态
  static const Color accentMatcha = accent;
  static const Color accentGreen = Color(0xFF4F7A58);
  static const Color accentWarnOrange = warningOrange;

  // ── 状态色（文字）──
  static const Color statusToday = Color(0xFFD4943A);
  static const Color statusOverdue = Color(0xFFD4523A);
  static const Color statusUpcoming = Color(0xFF365A70);
  static const Color statusDeadlineText = Color(0xFF875F28);

  // ── 状态色（背景）──
  static const Color statusOverdueBg = Color(0xFFFFF0F0);
  static const Color statusTodayBg = Color(0xFFFFF4F0);
  static const Color statusUpcomingBg = Color(0xFFEEF4F7);
  static const Color statusDeadlineBg = Color(0xFFFFF1DF);
  static const Color statusTodoBg = Color(0xFFEDF4F7);

  // ── 扩展状态令牌（旧页面也统一使用同一套语义颜色）──
  static const Color statusSuccessBg = Color(0xFFF1F5F2);
  static const Color statusSuccessBorder = Color(0xFFDDE7DF);
  static const Color statusSuccess = Color(0xFF5E7A62);
  static const Color statusSuccessStrong = Color(0xFF36543A);
  static const Color statusSuccessLightBg = Color(0xFFEDF7ED);
  static const Color backgroundWeekNear = Color(0xFFFCFAF7);
  static const Color backgroundWeekend = Color(0xFFFAFAF8);
  static const Color backgroundDeadlineRail = Color(0xFFFDFAF5);
  static const Color borderDeadlineRail = Color(0xFFEDE0C8);
  static const Color borderInputLegacy = Color(0xFFE8E0D5);
  static const Color statusDeadlineStrong = Color(0xFF72501F);
  static const Color statusDeadlineIcon = Color(0xFF8B6F47);
  static const Color statusError = statusOverdue;
  static const Color statusErrorStrong = Color(0xFFB23A2E);
  static const Color statusErrorBorder = Color(0xFFEAB8B3);
  static const Color contentOnAccent = Colors.white;
  static const Color transparent = Colors.transparent;
  static const Color shadowInk = Colors.black;

  // ═══════════════════════════════════════════════════════════════════════════
  // Spacing Scale
  // ═══════════════════════════════════════════════════════════════════════════
  static const double spaceXxs = 2;
  static const double spaceXs = 4;
  static const double spaceSm = 6;
  static const double spaceMd = 8;
  static const double spaceLg = 12;
  static const double spaceXl = 16;
  static const double spaceXxl = 20;
  static const double spaceXxxl = 24;
  static const double spaceHuge = 32;

  // 语义间距
  static const double cardPadding = 16;
  static const double sectionGap = 20;
  static const double pagePaddingHorizontal = 28;
  static const double pagePaddingVertical = 14;
  static const double listBottomPadding = 40;

  // ═══════════════════════════════════════════════════════════════════════════
  // Border Radius Scale
  // ═══════════════════════════════════════════════════════════════════════════
  static const double radiusXs = 4;
  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;
  static const double radiusFull = 999;

  // 语义圆角
  static const double radiusCard = radiusLg;
  static const double radiusChip = radiusSm;
  static const double radiusBadge = radiusXs;
  static const double radiusDialog = radiusXl;
  static const double radiusInput = radiusLg;
  static const double radiusButton = radiusLg;

  // ═══════════════════════════════════════════════════════════════════════════
  // Elevation / Shadow Helpers
  // ═══════════════════════════════════════════════════════════════════════════
  static BoxShadow shadowSubtle() => BoxShadow(
    color: Colors.black.withValues(alpha: 0.04),
    blurRadius: 8,
    offset: const Offset(0, 2),
  );

  static BoxShadow shadowMedium() => BoxShadow(
    color: Colors.black.withValues(alpha: 0.06),
    blurRadius: 12,
    offset: const Offset(0, 3),
  );

  static BoxShadow shadowCard() => BoxShadow(
    color: Colors.black.withValues(alpha: 0.03),
    blurRadius: 6,
    offset: const Offset(0, 1),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // Font
  // ═══════════════════════════════════════════════════════════════════════════
  static const List<String> fontFallback = [
    'Microsoft YaHei',
    'PingFang SC',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'SimHei',
  ];
  static const String appFontFamily = 'Microsoft YaHei';

  // ═══════════════════════════════════════════════════════════════════════════
  // Typography Scale — 预定义语义样式（静态常量）
  // ═══════════════════════════════════════════════════════════════════════════

  static const TextStyle headingPage = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w400,
    color: textHeading,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  static const TextStyle headingSection = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: textHeading,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  static const TextStyle headingZen = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: textHeading,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  static const TextStyle headingDialog = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w400,
    color: textBody,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  static const TextStyle bodyDialog = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textHeading,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  static const TextStyle dateDisplay = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textBody,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  static const TextStyle bodyMain = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: textBody,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textMuted,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: textMuted,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: textMuted,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  static const TextStyle chipText = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: interactiveBrown,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  static const TextStyle timeDisplay = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: accentMatcha,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  static const TextStyle emptyState = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textMuted,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  static const TextStyle emptyStateSub = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textCompleted,
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    letterSpacing: 0,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // TextStyle 工厂方法 — 保证 fontFamilyFallback 一致应用
  // ═══════════════════════════════════════════════════════════════════════════
  static TextStyle textStyle({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color color = textBody,
    double? height,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      decoration: decoration,
      fontFamily: appFontFamily,
      fontFamilyFallback: fontFallback,
      letterSpacing: 0,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Base
  // ═══════════════════════════════════════════════════════════════════════════

  static const TextStyle baseTextStyle = TextStyle(
    fontFamily: appFontFamily,
    fontFamilyFallback: fontFallback,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // Material 3 Theme
  // ═══════════════════════════════════════════════════════════════════════════

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: appFontFamily,
      scaffoldBackgroundColor: riceWhite,
      colorScheme: const ColorScheme.light(
        primary: accent,
        secondary: oatmeal,
        surface: riceWhite,
        error: warningOrange,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w300,
          fontFamily: appFontFamily,
          fontFamilyFallback: fontFallback,
          letterSpacing: 0,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          fontSize: 16,
          height: 1.6,
          fontWeight: FontWeight.w400,
          fontFamily: appFontFamily,
          fontFamilyFallback: fontFallback,
          letterSpacing: 0,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w400,
          fontFamily: appFontFamily,
          fontFamilyFallback: fontFallback,
          letterSpacing: 0,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: riceWhite,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w500,
          fontFamily: appFontFamily,
          fontFamilyFallback: fontFallback,
          letterSpacing: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: baseTextStyle),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(textStyle: baseTextStyle),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(textStyle: baseTextStyle),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: borderCard),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: backgroundMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: const BorderSide(color: accentMatcha, width: 1.5),
        ),
        hintStyle: const TextStyle(
          color: textSecondary,
          fontFamily: appFontFamily,
          fontFamilyFallback: fontFallback,
          letterSpacing: 0,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle: const TextStyle(
          color: riceWhite,
          fontFamily: appFontFamily,
          fontFamilyFallback: fontFallback,
          letterSpacing: 0,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: backgroundMuted,
        indicatorColor: interactivePressed,
        elevation: 0,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: interactivePressed,
        minWidth: 80,
      ),
    );
  }
}
