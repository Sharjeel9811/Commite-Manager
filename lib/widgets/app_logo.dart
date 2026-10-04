import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The Committee Manager mark: a group of members standing together.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 96,
    this.showShadow = true,
  });

  final double size;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.29),
        boxShadow: showShadow
            ? <BoxShadow>[
                BoxShadow(
                  color: AppColors.brandIndigo.withValues(alpha: 0.35),
                  blurRadius: size * 0.25,
                  offset: Offset(0, size * 0.1),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: _AppLogoPainter()),
    );
  }
}

class _AppLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    final Paint background = Paint()
      ..shader = const LinearGradient(
        colors: AppColors.primaryGradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds);
    canvas.drawRect(bounds, background);

    final Offset center = size.center(Offset.zero);
    final double unit = size.shortestSide;
    final Paint white = Paint()..color = Colors.white;

    // The smaller members sit behind the central member.
    _paintMember(canvas, center + Offset(-unit * 0.19, unit * 0.02), unit * 0.075, unit * 0.2, white);
    _paintMember(canvas, center + Offset(unit * 0.19, unit * 0.02), unit * 0.075, unit * 0.2, white);
    _paintMember(canvas, center + Offset(0, -unit * 0.015), unit * 0.105, unit * 0.29, white);
  }

  void _paintMember(Canvas canvas, Offset center, double headRadius, double bodyWidth, Paint paint) {
    canvas.drawCircle(center - Offset(0, headRadius * 1.15), headRadius, paint);
    final RRect body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center + Offset(0, headRadius * 1.1),
        width: bodyWidth,
        height: headRadius * 1.7,
      ),
      Radius.circular(headRadius * 0.55),
    );
    canvas.drawRRect(body, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
