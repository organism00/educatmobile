import 'package:flutter/material.dart';

class AppColors {
  // Primary colors - Softer, more accessible orange family
  static const Color primary = Color(0xFFE67E22);      // Warm Orange (softer)
  static const Color primaryLight = Color(0xFFF39C12);  // Lighter Orange (muted)
  static const Color primaryDark = Color(0xFFD35400);   // Darker Orange (rich)
  static const Color primarySoft = Color(0xFFFDEBD0);   // Very soft orange for backgrounds
  static const Color secondary = Color(0xFFE67E22);     // Consistent warm orange
  static const Color accent = Color(0xFFF5B041);        // Muted golden orange

  // Background gradients - Softer orange gradient
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE67E22), Color(0xFFD35400), Color(0xFFBA4A00)],
  );

  // Softer gradient for cards and widgets
  static const LinearGradient softGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFDEBD0), Color(0xFFFAD7A1), Color(0xFFF5B041)],
  );

  // Status colors
  static const Color success = Color(0xFF27AE60);
  static const Color error = Color(0xFFE74C3C);
  static const Color warning = Color(0xFFF39C12);
  static const Color info = Color(0xFF3498DB);

  // Neutral colors - Warm neutrals to complement orange
  static const Color white = Color(0xFFFFFFFF);
  static const Color cream = Color(0xFFFFF8F0);
  static const Color greyLight = Color(0xFFF5F5F5);
  static const Color grey = Color(0xFF95A5A6);
  static const Color greyDark = Color(0xFF7F8C8D);
  static const Color black = Color(0xFF2C3E50);
  static const Color textPrimary = Color(0xFF2C3E50);
  static const Color textSecondary = Color(0xFF7F8C8D);

  // Orange shades for different UI elements
  static const Color orange50 = Color(0xFFFFF3E0);
  static const Color orange100 = Color(0xFFFFE0B2);
  static const Color orange200 = Color(0xFFFFCC80);
  static const Color orange300 = Color(0xFFFFB74D);
  static const Color orange400 = Color(0xFFFFA726);
  static const Color orange500 = Color(0xFFE67E22);
  static const Color orange600 = Color(0xFFD35400);
  static const Color orange700 = Color(0xFFBA4A00);
  static const Color orange800 = Color(0xFFA04000);
  static const Color orange900 = Color(0xFF803300);
}