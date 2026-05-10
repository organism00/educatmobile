import 'package:flutter/material.dart';

class AppColors {
  // Primary colors - Orange for cards and accents
  static const Color primary = Color(0xFFE67E22);      // Warm Orange
  static const Color primaryLight = Color(0xFFF39C12);  // Lighter Orange
  static const Color primaryDark = Color(0xFFD35400);   // Darker Orange
  static const Color primarySoft = Color(0xFFFDEBD0);   // Very soft orange for backgrounds

  // Background - White for better accessibility
  static const Color background = Color(0xFFFFFFFF);
  static const Color backgroundLight = Color(0xFFF8F9FA);

  // Status colors
  static const Color success = Color(0xFF27AE60);
  static const Color error = Color(0xFFE74C3C);
  static const Color warning = Color(0xFFF39C12);
  static const Color info = Color(0xFF3498DB);

  // Neutral colors
  static const Color white = Color(0xFFFFFFFF);
  static const Color cream = Color(0xFFFFF8F0);
  static const Color greyLight = Color(0xFFF5F5F5);
  static const Color grey = Color(0xFF95A5A6);
  static const Color greyDark = Color(0xFF7F8C8D);
  static const Color black = Color(0xFF2C3E50);
  static const Color textPrimary = Color(0xFF2C3E50);
  static const Color textSecondary = Color(0xFF7F8C8D);

  // Gradient for cards
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE67E22), Color(0xFFF39C12)],
  );

  static const LinearGradient cardGradientLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFDEBD0), Color(0xFFFAD7A1)],
  );
}