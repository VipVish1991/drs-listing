import 'dart:typed_data';

import 'package:DrsListing/utils/image_optimizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  Uint8List encodeJpeg(img.Image image, {int quality = 90}) =>
      img.encodeJpg(image, quality: quality);

  img.Image solidImage(int width, int height, img.Color color) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: color);
    return image;
  }

  group('PrescriptionImageOptimizer.optimize', () {
    test('downscales a large landscape photo to the max edge', () {
      final original = encodeJpeg(
        solidImage(3000, 2000, img.ColorRgb8(200, 60, 60)),
      );

      final out = PrescriptionImageOptimizer.optimize(original);
      expect(out, isNotNull);

      final decoded = img.decodeImage(out!);
      expect(decoded, isNotNull);
      expect(
        decoded!.width,
        lessThanOrEqualTo(PrescriptionImageOptimizer.maxEdge),
      );
      expect(
        decoded.height,
        lessThanOrEqualTo(PrescriptionImageOptimizer.maxEdge),
      );
      // Aspect ratio preserved (3000×2000 → 1600×1066).
      expect(decoded.width / decoded.height, closeTo(1.5, 0.03));
      // Re-encoding at quality 80 must shrink the payload.
      expect(out.length, lessThan(original.length));
    });

    test('downscales a large portrait photo preserving aspect ratio', () {
      final original = encodeJpeg(
        solidImage(1500, 3000, img.ColorRgb8(60, 60, 200)),
      );

      final out = PrescriptionImageOptimizer.optimize(original);
      final decoded = img.decodeImage(out!);
      expect(decoded, isNotNull);
      expect(
        decoded!.width,
        lessThanOrEqualTo(PrescriptionImageOptimizer.maxEdge),
      );
      expect(
        decoded.height,
        lessThanOrEqualTo(PrescriptionImageOptimizer.maxEdge),
      );
      // Aspect ratio preserved (1500×3000 → 800×1600).
      expect(decoded.width / decoded.height, closeTo(0.5, 0.03));
    });

    test('never upscales a photo smaller than the max edge', () {
      final original = encodeJpeg(
        solidImage(800, 600, img.ColorRgb8(60, 200, 60)),
      );

      final out = PrescriptionImageOptimizer.optimize(original);
      final decoded = img.decodeImage(out!);
      expect(decoded, isNotNull);
      expect(decoded!.width, 800);
      expect(decoded.height, 600);
      // Still re-encoded as JPEG.
      expect(out, isNotNull);
    });

    test('returns null for undecodable bytes', () {
      final garbage = Uint8List.fromList(List<int>.filled(64, 0xFF));
      expect(PrescriptionImageOptimizer.optimize(garbage), isNull);
    });

    test('honours custom edge limit and quality', () {
      final original = encodeJpeg(
        solidImage(2000, 1000, img.ColorRgb8(200, 200, 60)),
      );

      final out = PrescriptionImageOptimizer.optimize(
        original,
        edgeLimit: 640,
        jpegQuality: 50,
      );
      final decoded = img.decodeImage(out!);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(640));
      expect(decoded.width / decoded.height, closeTo(2.0, 0.03));
    });
  });

  group('PrescriptionImageOptimizer.optimizePortrait', () {
    test('pads a 4:3 portrait photo onto a 9:16 white canvas, content intact',
        () {
      final original = encodeJpeg(
        solidImage(1200, 1600, img.ColorRgb8(200, 60, 60)),
      );

      final out = PrescriptionImageOptimizer.optimizePortrait(original);
      final decoded = img.decodeImage(out!);
      expect(decoded, isNotNull);
      // 1200×1600 → 1200×2133 canvas: exact 9:16 ratio, nothing cropped
      // (the photo still fills the full 1600px height).
      expect(decoded!.width, 1200);
      expect(decoded.height, 2133);
      expect(decoded.width / decoded.height, closeTo(9 / 16, 0.01));

      // Center pixel is the red photo; a top pixel is white padding —
      // proves the whole photo survived inside the canvas.
      final center = decoded.getPixel(600, 1066);
      expect(center.r, greaterThan(150));
      expect(center.g, lessThan(120));
      final top = decoded.getPixel(600, 3);
      expect(top.r, greaterThan(240));
      expect(top.g, greaterThan(240));
      expect(top.b, greaterThan(240));
    });

    test('pads a landscape photo onto a 9:16 white canvas, content intact',
        () {
      final original = encodeJpeg(
        solidImage(1200, 900, img.ColorRgb8(60, 60, 200)),
      );

      final out = PrescriptionImageOptimizer.optimizePortrait(original);
      final decoded = img.decodeImage(out!);
      expect(decoded, isNotNull);
      // 1200×900 → 1200×2133 canvas: exact 9:16 ratio, full width kept
      // (below the maxEdge cap, so nothing is downscaled away).
      expect(decoded!.width, 1200);
      expect(decoded.height, 2133);
      expect(decoded.width / decoded.height, closeTo(9 / 16, 0.01));

      final center = decoded.getPixel(600, 1066);
      expect(center.b, greaterThan(150));
      expect(center.r, lessThan(120));
      final top = decoded.getPixel(600, 3);
      expect(top.r, greaterThan(240));
      expect(top.g, greaterThan(240));
      expect(top.b, greaterThan(240));
    });

    test('keeps an already-9:16 photo unchanged (no padding)', () {
      final original = encodeJpeg(
        solidImage(900, 1600, img.ColorRgb8(200, 60, 60)),
      );

      final out = PrescriptionImageOptimizer.optimizePortrait(original);
      final decoded = img.decodeImage(out!);
      expect(decoded, isNotNull);
      expect(decoded!.width, 900);
      expect(decoded.height, 1600);
    });

    test('still honors the longest-edge cap after padding', () {
      final original = encodeJpeg(
        solidImage(4000, 6000, img.ColorRgb8(200, 200, 60)),
      );

      final out = PrescriptionImageOptimizer.optimizePortrait(original);
      final decoded = img.decodeImage(out!);
      expect(decoded, isNotNull);
      expect(
        decoded!.height,
        lessThanOrEqualTo(PrescriptionImageOptimizer.maxEdge),
      );
      expect(decoded.width / decoded.height, closeTo(9 / 16, 0.01));
    });

    test('returns null for undecodable bytes', () {
      final garbage = Uint8List.fromList(List<int>.filled(64, 0xFF));
      expect(PrescriptionImageOptimizer.optimizePortrait(garbage), isNull);
    });
  });
}
