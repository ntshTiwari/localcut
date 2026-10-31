import 'package:flutter/material.dart';

/// Creator familiar: red actions, neutral surfaces, and system light/dark mode.
abstract final class AppTheme {
  static const red = Color(0xffD90025);
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: red, brightness: brightness)
        .copyWith(
          primary: dark ? const Color(0xffFF6976) : red,
          onPrimary: dark ? Colors.black : Colors.white,
          primaryContainer: dark
              ? const Color(0xff44131C)
              : const Color(0xffFFF0F2),
          onPrimaryContainer: dark
              ? const Color(0xffFFD9DE)
              : const Color(0xff970018),
          secondary: dark ? const Color(0xffF2BE64) : const Color(0xff865600),
          secondaryContainer: dark
              ? const Color(0xff3A2D17)
              : const Color(0xffFFF1D5),
          onSecondaryContainer: dark
              ? const Color(0xffFFE0A3)
              : const Color(0xff5B3A00),
          tertiary: dark ? const Color(0xffC8C8C8) : const Color(0xff555555),
          surface: dark ? const Color(0xff151515) : Colors.white,
          surfaceContainerLowest: dark ? const Color(0xff0F0F0F) : Colors.white,
          surfaceContainerLow: dark
              ? const Color(0xff1D1D1D)
              : const Color(0xffF7F7F7),
          surfaceContainer: dark
              ? const Color(0xff222222)
              : const Color(0xffF1F1F1),
          surfaceContainerHigh: dark
              ? const Color(0xff262626)
              : const Color(0xffEDEDED),
          surfaceContainerHighest: dark
              ? const Color(0xff303030)
              : const Color(0xffE7E7E7),
          onSurface: dark ? const Color(0xffF1F1F1) : const Color(0xff171717),
          onSurfaceVariant: dark
              ? const Color(0xffAAAAAA)
              : const Color(0xff666666),
          outline: dark ? const Color(0xff777777) : const Color(0xff888888),
          outlineVariant: dark
              ? const Color(0xff363636)
              : const Color(0xffE0E0E0),
        );
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xff0F0F0F)
          : const Color(0xffFAFAFA),
    );
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: TextStyle(
              fontSize: 34,
              height: 1.12,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.1,
              color: scheme.onSurface,
            ),
            headlineSmall: TextStyle(
              fontSize: 26,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: -.6,
              color: scheme.onSurface,
            ),
            titleLarge: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -.4,
              color: scheme.onSurface,
            ),
            titleMedium: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
            bodyLarge: TextStyle(
              fontSize: 16,
              height: 1.5,
              color: scheme.onSurface,
            ),
            bodyMedium: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: scheme.onSurface,
            ),
          )
          .apply(fontFamily: 'Roboto'),
      appBarTheme: AppBarTheme(
        backgroundColor: base.scaffoldBackgroundColor,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -.7,
          color: scheme.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: red,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 50),
          shape: rounded,
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(48, 46),
          shape: rounded,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        showDragHandle: true,
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: red),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: red,
        thumbColor: red,
        inactiveTrackColor: scheme.outlineVariant,
        overlayColor: red.withValues(alpha: .12),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }
}

class LocalCutBrand extends StatelessWidget {
  const LocalCutBrand({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: compact ? 29 : 34,
        height: compact ? 22 : 26,
        decoration: BoxDecoration(
          color: AppTheme.red,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: compact ? 20 : 25,
        ),
      ),
      const SizedBox(width: 9),
      Text(
        'LocalCut',
        style: TextStyle(
          fontSize: compact ? 20 : 23,
          fontWeight: FontWeight.w700,
          letterSpacing: -.9,
        ),
      ),
    ],
  );
}
