import 'package:flutter/material.dart';

abstract final class AppColors {
  static const brand = Color(0xFFE8453C);
  static const background = Color(0xFFF7F7F9);
  static const ink = Color(0xFF1A1A1E);
  static const secondary = Color(0xFF5C5C66);
  static const muted = Color(0xFFA0A0AA);
  static const border = Color(0xFFE8E8EC);
  static const safe = Color(0xFF2B6FE3);
  static const caution = Color(0xFFF5A623);
  static const danger = Color(0xFFD7263D);
}

ThemeData buildAppTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    primary: AppColors.brand,
    surface: Colors.white,
  ),
  fontFamily: 'Pretendard',
  textTheme: const TextTheme(
    headlineSmall: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
    titleLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      color: AppColors.secondary,
      height: 1.45,
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
);
