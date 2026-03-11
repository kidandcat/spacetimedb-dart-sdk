import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DiscordColors {
  DiscordColors._();

  // Backgrounds
  static const Color backgroundDarkest = Color(0xFF1E1F22);
  static const Color backgroundDark = Color(0xFF2B2D31);
  static const Color backgroundPrimary = Color(0xFF313338);
  static const Color backgroundSecondary = Color(0xFF2B2D31);
  static const Color backgroundTertiary = Color(0xFF1E1F22);
  static const Color backgroundFloating = Color(0xFF111214);
  static const Color backgroundModifier = Color(0x0BFFFFFF);
  static const Color backgroundModifierHover = Color(0x0FFFFFFF);
  static const Color backgroundModifierActive = Color(0x14FFFFFF);
  static const Color backgroundModifierSelected = Color(0x0FFFFFFF);
  static const Color backgroundModifierAccent = Color(0x14FFFFFF);

  // Server sidebar
  static const Color serverSidebarBg = Color(0xFF1E1F22);

  // Channel sidebar
  static const Color channelSidebarBg = Color(0xFF2B2D31);

  // Chat area
  static const Color chatBg = Color(0xFF313338);

  // Member list
  static const Color memberListBg = Color(0xFF2B2D31);

  // Brand colors
  static const Color blurple = Color(0xFF5865F2);
  static const Color blurpleHover = Color(0xFF4752C4);
  static const Color green = Color(0xFF248046);
  static const Color greenOnline = Color(0xFF23A55A);
  static const Color yellow = Color(0xFFF0B132);
  static const Color red = Color(0xFFDA373C);
  static const Color fuchsia = Color(0xFFEB459E);

  // Text
  static const Color textNormal = Color(0xFFDBDEE1);
  static const Color textMuted = Color(0xFF949BA4);
  static const Color textFaint = Color(0xFF6D6F78);
  static const Color textLink = Color(0xFF00A8FC);
  static const Color textPositive = Color(0xFF23A55A);
  static const Color textDanger = Color(0xFFDA373C);
  static const Color textBrand = Color(0xFF5865F2);
  static const Color headerPrimary = Color(0xFFF2F3F5);
  static const Color headerSecondary = Color(0xFFB5BAC1);

  // Input
  static const Color inputBg = Color(0xFF383A40);
  static const Color inputBorder = Color(0xFF1E1F22);

  // Divider
  static const Color divider = Color(0xFF3F4147);

  // Scrollbar
  static const Color scrollbarThin = Color(0xFF1A1B1E);
  static const Color scrollbarAuto = Color(0xFF2B2D31);

  // Status colors
  static const Color statusOnline = Color(0xFF23A55A);
  static const Color statusIdle = Color(0xFFF0B132);
  static const Color statusDnd = Color(0xFFF23F43);
  static const Color statusOffline = Color(0xFF80848E);

  // Mention
  static const Color mentionBg = Color(0x1E5865F2);
  static const Color mentionHoverBg = Color(0x3D5865F2);
}

class DiscordTheme {
  DiscordTheme._();

  static ThemeData dark() {
    final base = ThemeData.dark();
    final textTheme = GoogleFonts.notoSansTextTheme(base.textTheme).apply(
      bodyColor: DiscordColors.textNormal,
      displayColor: DiscordColors.headerPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: DiscordColors.chatBg,
      canvasColor: DiscordColors.backgroundFloating,
      cardColor: DiscordColors.backgroundSecondary,
      dividerColor: DiscordColors.divider,
      primaryColor: DiscordColors.blurple,
      colorScheme: const ColorScheme.dark(
        primary: DiscordColors.blurple,
        secondary: DiscordColors.blurple,
        surface: DiscordColors.backgroundPrimary,
        error: DiscordColors.red,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: DiscordColors.textNormal,
        onError: Colors.white,
      ),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: DiscordColors.chatBg,
        foregroundColor: DiscordColors.headerPrimary,
        elevation: 1,
        shadowColor: Colors.black26,
      ),
      iconTheme: const IconThemeData(
        color: DiscordColors.textMuted,
        size: 20,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DiscordColors.inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: DiscordColors.textMuted,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DiscordColors.backgroundPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: DiscordColors.headerPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: DiscordColors.backgroundFloating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(DiscordColors.scrollbarThin),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(6),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: DiscordColors.backgroundFloating,
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: DiscordColors.headerPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
