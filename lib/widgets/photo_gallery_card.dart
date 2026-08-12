import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../models/doctor_model.dart';
import '../services/places_service.dart';
import 'zoomable_image.dart';

// ════════════════════════════════════════════════════════════════════
// Shared photo gallery — shows all Google Places photos for a
// doctor / clinic / hospital in a 3-column grid with a fullscreen
// viewer. Used by the Doctor Detail screen and the Doctor Profile
// screen so the gallery renders identically everywhere.
// ════════════════════════════════════════════════════════════════════
class PhotoGalleryCard extends StatelessWidget {
  final DoctorModel doctor;
  final bool isDark;

  const PhotoGalleryCard({
    super.key,
    required this.doctor,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final photos = doctor.photos;
    if (photos.isEmpty) return const SizedBox.shrink();

    return _GallerySectionCard(
      isDark: isDark,
      header: _GallerySectionHeader(
        icon: Icons.photo_library_rounded,
        iconColor: AppColors.accent,
        title: 'Photos (${photos.length})',
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1,
        ),
        // Show at most 9 photos in the grid; remaining are counted
        // in the "+N more" overlay on the last visible tile.
        itemCount: photos.length > 9 ? 9 : photos.length,
        itemBuilder: (context, index) {
          final photoUrl = PlacesService().getPhotoUrl(
            photos[index],
            maxWidth: 300,
          );
          if (photoUrl == null) {
            return _photoPlaceholder();
          }
          return GestureDetector(
            onTap: () => _showPhotoFullscreen(context, index, photos),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _photoPlaceholder(),
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return _photoPlaceholder();
                    },
                  ),
                  // "+N more" overlay on the last visible tile —
                  // frosted-glass (Instagram style) with BackdropFilter
                  // blur over the underlying photo.
                  if (index == 8 && photos.length > 9)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(90),
                          ),
                          child: Center(
                            child: Text(
                              '+${photos.length - 9} more',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(15),
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

  void _showPhotoFullscreen(
    BuildContext context,
    int initialIndex,
    List<String> photos,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullscreenPhotoGallery(
          photos: photos,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

/// Full-screen photo viewer with swipe-to-navigate + pinch and
/// double-tap zoom (via the shared [ZoomableImage]).
class FullscreenPhotoGallery extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;

  const FullscreenPhotoGallery({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<FullscreenPhotoGallery> createState() => _FullscreenPhotoGalleryState();
}

class _FullscreenPhotoGalleryState extends State<FullscreenPhotoGallery> {
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
              '${_currentIndex + 1} / ${widget.photos.length}',
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
        itemCount: widget.photos.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemBuilder: (context, index) {
          final photoUrl = PlacesService().getPhotoUrl(
            widget.photos[index],
            maxWidth: 1200,
          );
          return Center(
            child: ZoomableImage(
              child: photoUrl != null
                  ? Image.network(
                      photoUrl,
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
                          child: CircularProgressIndicator(
                            color: Colors.white54,
                          ),
                        );
                      },
                    )
                  : const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Private building blocks (self-contained copy of the section card +
// header used across the detail screen, so this widget is portable).
// ════════════════════════════════════════════════════════════════════
class _GallerySectionCard extends StatelessWidget {
  final bool isDark;
  final Widget header;
  final Widget child;

  const _GallerySectionCard({
    required this.isDark,
    required this.header,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, const SizedBox(height: 16), child],
      ),
    );
  }
}

class _GallerySectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;

  const _GallerySectionHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: iconColor.withAlpha(30),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppColors.textHeading,
          ),
        ),
      ],
    );
  }
}
