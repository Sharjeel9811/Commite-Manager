import 'package:flutter/material.dart';

export 'app_spacing.dart';

/// The single source of truth for every colour used by the application.
///
/// Widgets never invent their own colours: they either use a
/// `Theme.of(context).colorScheme` role or one of the semantic colours here.
class AppColors {
  const AppColors._();

  // Brand seeds
  static const Color brandIndigo = Color(0xFF4F46E5);
  static const Color brandTeal = Color(0xFF0F9D8F);
  static const Color brandAmber = Color(0xFFF59E0B);
  static const Color brandRose = Color(0xFFE11D48);

  // Semantic status colours (identical intent in light and dark)
  static const Color success = Color(0xFF16A34A);
  static const Color successContainerDark = Color(0xFF14532D);
  static const Color onSuccessContainerDark = Color(0xFFBBF7D0);

  static const Color warning = Color(0xFFD97706);
  static const Color warningContainerDark = Color(0xFF78350F);
  static const Color onWarningContainerDark = Color(0xFFFDE68A);

  static const Color danger = Color(0xFFDC2626);
  static const Color dangerContainerDark = Color(0xFF7F1D1D);
  static const Color onDangerContainerDark = Color(0xFFFECACA);

  static const Color info = Color(0xFF2563EB);
  static const Color infoContainerDark = Color(0xFF1E3A8A);
  static const Color onInfoContainerDark = Color(0xFFBFDBFE);

  static const Color neutral = Color(0xFF64748B);
  static const Color neutralContainerDark = Color(0xFF334155);
  static const Color onNeutralContainerDark = Color(0xFFE2E8F0);

  // Gradients used by hero cards
  static const List<Color> primaryGradient = <Color>[
    Color(0xFF6366F1),
    Color(0xFF4F46E5),
    Color(0xFF4338CA),
  ];

  static const List<Color> successGradient = <Color>[Color(0xFF34D399), Color(0xFF059669)];

  static const List<Color> dangerGradient = <Color>[Color(0xFFFB7185), Color(0xFFE11D48)];

  static const List<Color> warningGradient = <Color>[Color(0xFFFBBF24), Color(0xFFD97706)];

  // Pie / bar chart palette, ordered for maximum visual separation
  static const List<Color> chartPalette = <Color>[
    Color(0xFF4F46E5),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
  ];
}
