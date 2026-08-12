import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Client-side photo optimization for prescription uploads.
///
/// The booking-page Edge Function already downscales photos to 2560px
/// before storing them, but that resize happens after the bytes cross the
/// network. Optimizing here first keeps the upload request itself small,
/// which matters on slow connections. Prescription text must stay legible
/// when the patient zooms in, so the cap is generous and the JPEG quality
/// high (a second generation-lossy encode at the same quality is minimal).
class PrescriptionImageOptimizer {
  /// Longest-edge cap in pixels — matches the Edge Function's 2560px
  /// target, so a client-optimized photo needs no further server work.
  static const int maxEdge = 2560;

  /// JPEG quality used for the re-encoded photo.
  static const int quality = 92;

  /// Target width:height ratio for stored prescriptions — 9:16 portrait,
  /// the same framing used by the preview sheet and the gallery grid.
  static const double portraitAspect = 9 / 16;

  /// Optimize [bytes] preserving its aspect ratio (see [_optimize]).
  static Uint8List? optimize(
    Uint8List bytes, {
    int edgeLimit = maxEdge,
    int jpegQuality = quality,
  }) =>
      _optimize(bytes, edgeLimit: edgeLimit, jpegQuality: jpegQuality);

  /// Optimize [bytes] for portrait 9:16 display: fits the WHOLE photo
  /// inside a 9:16 white canvas (letterboxing — never crops, so no
  /// prescription text can be lost), then runs the same downscale +
  /// sharpen + re-encode pipeline as [optimize]. The result is exactly
  /// what the doctor previews and what the gallery thumbnails show
  /// edge-to-edge; the white bars read as paper margins.
  static Uint8List? optimizePortrait(Uint8List bytes) =>
      _optimize(bytes, fitAspectRatio: portraitAspect);

  /// Decodes [bytes] as an image, bakes any EXIF rotation into the pixels,
  /// optionally fits the image inside a [fitAspectRatio] white canvas
  /// (letterbox, never crop), downscales the longest edge to at most
  /// [edgeLimit] pixels (aspect ratio preserved; never upscales), and
  /// re-encodes as a JPEG at [jpegQuality]. When a downscale actually
  /// happened, a gentle sharpen is applied first to counteract the softness
  /// the resize adds — this keeps prescription text edges crisp when the
  /// patient zooms in.
  ///
  /// Returns `null` when [bytes] can't be decoded as an image, so callers
  /// can fall back to the original bytes rather than fail the upload.
  static Uint8List? _optimize(
    Uint8List bytes, {
    int edgeLimit = maxEdge,
    int jpegQuality = quality,
    double? fitAspectRatio,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // Bake EXIF orientation into the pixels: the server-side Jimp decoder
    // can't read EXIF, so this guarantees the photo is upright even if the
    // picker returned original-format bytes.
    var image = img.bakeOrientation(decoded);

    // Downscale before padding so the letterbox canvas never gets huge.
    image = _fitWithinLongestEdge(image, edgeLimit);

    if (fitAspectRatio != null && fitAspectRatio > 0) {
      image = _padToAspectRatio(image, fitAspectRatio);
    }

    // Padding can grow the canvas beyond the cap (the white bars) — clamp
    // again so the stored file stays within the server's target.
    image = _fitWithinLongestEdge(image, edgeLimit);

    return img.encodeJpg(image, quality: jpegQuality);
  }

  /// Downscales [image] so its longest edge is at most [edgeLimit]
  /// (aspect preserved; no-op when already within the limit). A gentle
  /// sharpen is applied whenever a resize happened to restore edge
  /// contrast — without halos or noise amplification on clean photos.
  static img.Image _fitWithinLongestEdge(img.Image image, int edgeLimit) {
    final longestEdge =
        image.width >= image.height ? image.width : image.height;
    if (longestEdge <= edgeLimit) return image;

    final scale = edgeLimit / longestEdge;
    final resized = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
    // Standard 3x3 sharpen kernel (sums to 1 → no brightness shift)
    // blended at 40% strength. Mirrors the booking-page function's
    // sharpen, which only runs when IT has to downscale.
    return img.convolution(
      resized,
      filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
      amount: 0.4,
    );
  }

  /// Fits [image] inside a white canvas with width:height = [aspect]
  /// (letterboxing on the shorter axis), returning a canvas of exactly that
  /// ratio. Never crops or scales the photo itself — every pixel survives.
  /// Returns [image] unchanged when it already matches the ratio.
  static img.Image _padToAspectRatio(img.Image image, double aspect) {
    final ratio = image.width / image.height;
    if ((ratio - aspect).abs() < 1e-6) return image;

    int canvasWidth, canvasHeight;
    if (ratio > aspect) {
      // Photo wider than the target → same width, pad top/bottom.
      canvasWidth = image.width;
      canvasHeight = (image.width / aspect).round();
    } else {
      // Photo taller than the target → same height, pad left/right.
      canvasHeight = image.height;
      canvasWidth = (image.height * aspect).round();
    }

    final canvas = img.Image(width: canvasWidth, height: canvasHeight);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(
      canvas,
      image,
      dstX: ((canvasWidth - image.width) / 2).round(),
      dstY: ((canvasHeight - image.height) / 2).round(),
    );
    return canvas;
  }
}
