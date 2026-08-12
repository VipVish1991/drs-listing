import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import 'zoomable_image.dart';

// ════════════════════════════════════════════════════════════════════
// Prescription gallery — shows uploaded prescription photos (public
// Supabase Storage URLs) in a 3-column grid with a fullscreen viewer.
// Used by the appointment details sheet (both doctor and patient sides)
// and by the doctor's completed appointment card.
// ════════════════════════════════════════════════════════════════════
class PrescriptionGallery extends StatelessWidget {
  final List<String> urls;
  final bool isDark;

  /// When true, renders a compact horizontal thumbnail strip instead of
  /// the 3-column grid — used inside the doctor's appointment card,
  /// which is wrapped in an [IntrinsicHeight] (a shrink-wrapped GridView
  /// can't provide intrinsic dimensions, so the strip avoids that).
  final bool compact;

  /// When set, tapping a thumbnail invokes this instead of the default
  /// per-gallery fullscreen viewer — e.g. the patient-history timeline
  /// opens the shared swipeable all-prescriptions gallery at that image.
  /// Receives the tapped thumbnail's index within [urls].
  final void Function(BuildContext context, int index)? onThumbnailTap;

  const PrescriptionGallery({
    super.key,
    required this.urls,
    this.isDark = false,
    this.compact = false,
    this.onThumbnailTap,
  });

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    if (compact) return _buildCompactStrip(context);
    return _buildGrid(context);
  }

  /// Horizontal scrollable strip of fixed-size thumbnails.
  Widget _buildCompactStrip(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.medication_rounded,
              size: 15,
              color: AppColors.accent,
            ),
            const SizedBox(width: 6),
            Text(
              urls.length == 1
                  ? 'Prescription'
                  : 'Prescriptions (${urls.length})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : AppColors.textCaption,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Portrait 9:16 thumbnails (54×96) — prescriptions are stored as
        // 9:16 pages, so each thumbnail shows the whole page edge-to-edge.
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () {
                  final custom = onThumbnailTap;
                  if (custom != null) {
                    custom(context, index);
                    return;
                  }
                  _openFullscreen(context, index);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    urls[index],
                    width: 54,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _placeholder(),
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return _placeholder();
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 3-column grid of thumbnails with fullscreen viewer.
  Widget _buildGrid(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppColors.accent.withAlpha(30),
              ),
              child: const Icon(
                Icons.medication_rounded,
                color: AppColors.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              urls.length == 1
                  ? 'Prescription'
                  : 'Prescriptions (${urls.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppColors.textHeading,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // 9:16 portrait cells — uploaded prescriptions are 9:16 pages, so
          // each thumbnail is the full page with no crop.
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 9 / 16,
          ),
          itemCount: urls.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () {
                final custom = onThumbnailTap;
                if (custom != null) {
                  custom(context, index);
                  return;
                }
                _openFullscreen(context, index);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  urls[index],
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _placeholder(),
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return _placeholder();
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.accent.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(
          Icons.image_rounded,
          color: AppColors.textDisabled,
          size: 28,
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrescriptionViewer(
          urls: urls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

/// Full-screen prescription viewer with swipe navigation + pinch and
/// double-tap zoom. Public so the appointment cards' "Click" row can open
/// it directly.
class PrescriptionViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const PrescriptionViewer({
    super.key,
    required this.urls,
    required this.initialIndex,
  });

  @override
  State<PrescriptionViewer> createState() => PrescriptionViewerState();
}

class PrescriptionViewerState extends State<PrescriptionViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_currentIndex + 1} / ${widget.urls.length}',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                AppConstants.zoomHintText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.urls.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          return Center(
            child: ZoomableImage(
              child: Image.network(
                widget.urls[index],
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white54),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
