import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const brand = Color(0xff0891b2);
  static const brandDark = Color(0xff0e7490);
  static const brandSoft = Color(0xffecfeff);
  static const brandSoftest = Color(0xfff0fdff);
  static const ink = Color(0xff172033);
  static const muted = Color(0xff64748b);
  static const line = Color(0xffdfe7f1);
  static const panel = Color(0xffffffff);
  static const canvas = Color(0xfff5f7fb);
  static const danger = Color(0xffdc2626);
}

ThemeData buildYSTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      primary: AppColors.brand,
      secondary: AppColors.brandDark,
      surface: AppColors.panel,
      brightness: Brightness.light,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.canvas,
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    visualDensity: VisualDensity.compact,
    textTheme: base.textTheme.apply(fontSizeFactor: 0.93),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: AppColors.panel,
      foregroundColor: AppColors.ink,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 17,
        fontWeight: FontWeight.w900,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xfffbfdff),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.brand, width: 1.2),
      ),
      labelStyle:
          const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700),
      hintStyle: const TextStyle(color: Color(0xff94a3b8)),
      prefixIconColor: const Color(0xff728097),
      suffixIconColor: const Color(0xff728097),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(38, 38),
        padding: const EdgeInsets.all(7),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.panel,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.panel,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Color(0xffcbd5e1),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dividerTheme:
        const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
  );
}

class BrandLogo extends StatelessWidget {
  const BrandLogo(
      {super.key, this.size = 52, this.padding = 7, this.shadow = true});

  final double size;
  final double padding;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.14)),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: const Color(0xff0f172a).withValues(alpha: 0.10),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: ClipRect(
        child: Image.asset(
          'assets/logochat.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

String initials(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  final parts =
      trimmed.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return '${parts.first.characters.first}${parts.last.characters.first}'
      .toUpperCase();
}

class YSAvatar extends StatelessWidget {
  const YSAvatar({
    super.key,
    required this.label,
    this.imageUrl,
    this.size = 44,
    this.online,
  });

  final String label;
  final String? imageUrl;
  final double size;
  final bool? online;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl?.isNotEmpty == true;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: size / 2,
            backgroundColor: AppColors.brandSoft,
            foregroundColor: AppColors.brandDark,
            backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
            child: hasImage
                ? null
                : Text(
                    initials(label),
                    style: TextStyle(
                        fontSize: size * 0.34, fontWeight: FontWeight.w900),
                  ),
          ),
          if (online != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: online!
                      ? const Color(0xff22c55e)
                      : const Color(0xffcbd5e1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: AppColors.muted),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.muted, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
