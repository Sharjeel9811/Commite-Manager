// Generates the launcher icons and the Play Store listing icon.
//
// Run with:  dart run tool/generate_icons.dart
//
// The mark is a ring of members around a collected pot: the one idea the app
// actually sells. It is drawn in code rather than committed as binary art so a
// brand colour change is a one-line edit and a re-run, and so every density
// stays pixel-consistent instead of being resampled from one large PNG.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// The brand indigo the app already uses in its Material theme.
const _indigoTop = <int>[0xFF, 0x63, 0x6F, 0xF1];
const _indigoBottom = <int>[0xFF, 0x43, 0x38, 0xCA];
const _white = <int>[0xFF, 0xFF, 0xFF, 0xFF];

/// Launcher densities. Android expects the icon at these exact pixel sizes.
const Map<String, int> _mipmapSizes = <String, int>{
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

/// Android 12+ shows the icon at 108dp with only the middle 72dp guaranteed
/// visible, so the adaptive foreground is padded well inside that safe zone.
const int _adaptiveForegroundSize = 432;
const int _adaptiveBackgroundSize = 432;

void main() {
  const String resDir = 'android/app/src/main/res';

  // Legacy square icons, used on API 24-25 and by anything that reads
  // `ic_launcher.png` directly.
  for (final MapEntry<String, int> entry in _mipmapSizes.entries) {
    final String path = '$resDir/${entry.key}/ic_launcher.png';
    _write(path, _renderLegacy(entry.value));
    stdout.writeln('wrote $path (${entry.value}x${entry.value})');
  }

  // Round variants. Launchers that draw a circular icon (and the Play listing's
  // rounded rendering) look wrong against a square bitmap, so these exist as
  // their own files rather than relying on the launcher to crop.
  for (final MapEntry<String, int> entry in _mipmapSizes.entries) {
    final String path = '$resDir/${entry.key}/ic_launcher_round.png';
    _write(path, _renderRound(entry.value));
    stdout.writeln('wrote $path (${entry.value}x${entry.value})');
  }

  // Play Store listing icon: 512x512 PNG, 32-bit, no transparency.
  const String storeIcon = 'store/icon-512.png';
  Directory('store').createSync(recursive: true);
  _write(storeIcon, _renderRound(512, opaque: true));
  stdout.writeln('wrote $storeIcon (512x512)');

  // Adaptive layers for API 26+ (and the Android 12 splash screen).
  for (final String density in <String>['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
    final int scale = switch (density) {
      'mdpi' => 1,
      'hdpi' => 2,
      'xhdpi' => 3,
      'xxhdpi' => 4,
      'xxxhdpi' => 5,
      _ => 1,
    };
    final String dir = '$resDir/drawable-$density';
    Directory(dir).createSync(recursive: true);

    final String foreground = '$dir/ic_launcher_foreground.png';
    _write(foreground, _renderForeground(_adaptiveForegroundSize * scale ~/ 4));
    stdout.writeln('wrote $foreground');

    final String background = '$dir/ic_launcher_background.png';
    _write(background, _renderGradient(_adaptiveBackgroundSize * scale ~/ 4));
    stdout.writeln('wrote $background');
  }
}

/// The complete icon: the mark on the brand gradient.
///
/// [legacy] drops the rounded-square shape and the padding, because pre-26
/// launchers draw the bitmap as-is and a pre-rounded icon looks wrong in a
/// circular or squircle mask applied later.
img.Image _renderLegacy(int size, {bool opaque = false}) {
  final img.Image canvas = _renderGradient(size, opaque: opaque);
  _paintMark(canvas, center: size / 2, radius: size * 0.34, ring: size * 0.058);
  return canvas;
}

/// The icon on a true circle, for launchers that ask for a round bitmap.
img.Image _renderRound(int size, {bool opaque = false}) {
  final img.Image canvas = _renderGradient(size, opaque: opaque);
  // Punch the corners out so the gradient does not bleed past the circle.
  final double c = size / 2;
  final double r = size / 2;
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final double dx = x + 0.5 - c;
      final double dy = y + 0.5 - c;
      if (math.sqrt(dx * dx + dy * dy) > r) canvas.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  // Slightly smaller mark so it is not clipped by the circle's edge.
  _paintMark(canvas, center: c, radius: size * 0.32, ring: size * 0.055);
  return canvas;
}

/// Just the mark, on transparency, centred in the adaptive safe zone.
img.Image _renderForeground(int size) {
  final img.Image canvas = img.Image(width: size, height: size, numChannels: 4);
  // The safe zone is the middle 72/108 of the canvas, so the mark is drawn
  // against that rather than the full bitmap.
  final double safe = size * (72 / 108);
  _paintMark(canvas, center: size / 2, radius: safe * 0.36, ring: safe * 0.062);
  return canvas;
}

/// The brand gradient, top-left lighter to bottom-right darker.
img.Image _renderGradient(int size, {bool opaque = false}) {
  final img.Image canvas = img.Image(width: size, height: size, numChannels: 4);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      // Diagonal so the gradient still reads when the icon is masked.
      final double t = (x + y) / (2 * (size - 1));
      canvas.setPixelRgba(
        x,
        y,
        _mix(_indigoTop[0], _indigoBottom[0], t),
        _mix(_indigoTop[1], _indigoBottom[1], t),
        _mix(_indigoTop[2], _indigoBottom[2], t),
        opaque ? 255 : 255,
      );
    }
  }
  return canvas;
}

/// A ring of members with a filled pot in the middle.
void _paintMark(img.Image canvas, {required double center, required double radius, required double ring}) {
  const int members = 7;
  const double startAngle = -math.pi / 2;

  // The pot: a solid disc with a smaller ring cut out of it, so it reads as a
  // coin rather than a dot at small sizes.
  _fillCircle(canvas, center, center, radius * 0.42, _white);
  _strokeCircle(canvas, center, center, radius * 0.20, 1.0, _withAlpha(_indigoBottom, 0));

  // The members sit on the orbit around the pot.
  final double memberRadius = radius * 0.115;
  for (int i = 0; i < members; i++) {
    final double angle = startAngle + (i * 2 * math.pi / members);
    final double x = center + radius * math.cos(angle);
    final double y = center + radius * math.sin(angle);
    _fillCircle(canvas, x, y, memberRadius, _white);
  }

  // A thin ring ties the members to the pot and keeps the mark from looking
  // like loose confetti when it is only 48 pixels across.
  _strokeCircle(canvas, center, center, radius, ring, _white);
}

void _fillCircle(img.Image canvas, double cx, double cy, double r, List<int> color) {
  final int minX = math.max(0, (cx - r - 1).floor());
  final int maxX = math.min(canvas.width - 1, (cx + r + 1).ceil());
  final int minY = math.max(0, (cy - r - 1).floor());
  final int maxY = math.min(canvas.height - 1, (cy + r + 1).ceil());

  for (int y = minY; y <= maxY; y++) {
    for (int x = minX; x <= maxX; x++) {
      final double dx = x + 0.5 - cx;
      final double dy = y + 0.5 - cy;
      final double distance = math.sqrt(dx * dx + dy * dy);
      if (distance <= r) {
        canvas.setPixelRgba(x, y, color[0], color[1], color[2], color[3]);
      }
    }
  }
}

void _strokeCircle(img.Image canvas, double cx, double cy, double r, double thickness, List<int> color) {
  final double outer = r + thickness / 2;
  final double inner = r - thickness / 2;
  final int minX = math.max(0, (cx - outer - 1).floor());
  final int maxX = math.min(canvas.width - 1, (cx + outer + 1).ceil());
  final int minY = math.max(0, (cy - outer - 1).floor());
  final int maxY = math.min(canvas.height - 1, (cy + outer + 1).ceil());

  for (int y = minY; y <= maxY; y++) {
    for (int x = minX; x <= maxX; x++) {
      final double dx = x + 0.5 - cx;
      final double dy = y + 0.5 - cy;
      final double distance = math.sqrt(dx * dx + dy * dy);
      if (distance <= outer && distance >= inner && color[3] != 0) {
        canvas.setPixelRgba(x, y, color[0], color[1], color[2], color[3]);
      }
    }
  }
}

List<int> _withAlpha(List<int> color, int alpha) => <int>[color[0], color[1], color[2], alpha];

int _mix(int from, int to, double t) => (from + (to - from) * t).round().clamp(0, 255);

void _write(String path, img.Image image) {
  File(path).writeAsBytesSync(img.encodePng(image, level: 9));
}
