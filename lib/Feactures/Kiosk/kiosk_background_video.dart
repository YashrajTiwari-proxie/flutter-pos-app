import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../Database/device_identity_service.dart';
import '../../Database/remote_asset_cache.dart';

/// Looping, muted, full-bleed background video for the kiosk's idle/start screen. Plays
/// [networkUrl] (set by a restaurant manager on the admin dashboard - see
/// `DeviceIdentityService.kioskVideoUrl`) when present - downloaded once through
/// [RemoteAssetCache] and played from that local file after (never re-fetched from the server on
/// a later app restart, only when the URL itself changes). No video configured (or it fails to
/// load) means no video at all here - deliberately NOT falling back to a bundled placeholder
/// asset, since a restaurant that hasn't set one yet should get the branded [_FallbackBackground]
/// animation, not a stand-in video that isn't actually theirs.
class KioskBackgroundVideo extends StatefulWidget {
  const KioskBackgroundVideo({super.key, this.networkUrl});

  final String? networkUrl;

  @override
  State<KioskBackgroundVideo> createState() => _KioskBackgroundVideoState();
}

class _KioskBackgroundVideoState extends State<KioskBackgroundVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final networkUrl = widget.networkUrl;
    if (networkUrl == null) {
      _failed = true;
      return;
    }
    _load(networkUrl);
  }

  Future<void> _load(String networkUrl) async {
    VideoPlayerController controller;
    try {
      final file = await RemoteAssetCache.instance.file(networkUrl);
      controller = VideoPlayerController.file(file);
    } catch (_) {
      // Disk caching failed for some reason - fall back to streaming it directly (the old
      // behavior, no local caching) rather than showing nothing. A broken cache should never
      // mean a broken video.
      controller = VideoPlayerController.networkUrl(Uri.parse(networkUrl));
    }
    controller
        .initialize()
        .then((_) {
          if (!mounted) {
            controller.dispose();
            return;
          }
          controller
            ..setLooping(true)
            ..setVolume(0)
            ..play();
          setState(() => _controller = controller);
        })
        .catchError((_) {
          controller.dispose();
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed || controller == null || !controller.value.isInitialized) {
      return const _FallbackBackground();
    }
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

/// Shown whenever no video (neither a manager-configured one nor a bundled local asset) is
/// available - a slow, softly shifting gradient sweep in shades of this restaurant's own accent
/// color (not the `cool_background_animation` package's `GradientMeshBackground` - that one had
/// a visible white edge artifact where its grid didn't quite reach the corners of the canvas; a
/// plain animated `LinearGradient` always fills its box exactly, so there's no edge to see),
/// with the kiosk's own header logo centered on top. Deliberately slow (16s) and gentle - a calm
/// stand-in background, not something meant to draw attention to itself.
class _FallbackBackground extends StatefulWidget {
  const _FallbackBackground();

  @override
  State<_FallbackBackground> createState() => _FallbackBackgroundState();
}

class _FallbackBackgroundState extends State<_FallbackBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    // A handful of tints/shades of the accent (not just the flat color itself) so the sweep
    // reads as distinct bands, the same way the reference clip's gradient had several shades of
    // blue rather than one flat color animating.
    final colors = [
      Color.lerp(accent, Colors.white, 0.55)!,
      accent,
      Color.lerp(accent, Colors.black, 0.35)!,
    ];
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.lerp(
                Alignment.topLeft,
                Alignment.centerLeft,
                t,
              )!,
              end: Alignment.lerp(
                Alignment.bottomRight,
                Alignment.centerRight,
                t,
              )!,
              colors: colors,
            ),
          ),
          child: child,
        );
      },
      // Sits in the upper-middle area rather than dead center - dead center reads as
      // competing with the bottom island's own visual weight, and left it feeling
      // unbalanced/empty below.
      child: Align(
        alignment: const Alignment(0, -0.35),
        child: ValueListenableBuilder<int>(
          valueListenable: DeviceIdentityService.instance.remoteConfigVersion,
          builder: (context, _, _) {
            final logoBytes =
                DeviceIdentityService.instance.kioskHeaderLogoBytes;
            if (logoBytes == null) {
              // No logo configured - just the animation, no placeholder icon standing in for a
              // brand mark that doesn't exist.
              return const SizedBox.shrink();
            }
            // Plain logo, no frosted-glass panel behind it - sized to its own aspect ratio (no
            // stretching/cropping into a fixed shape).
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260, maxHeight: 140),
              child: Image.memory(
                logoBytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            );
          },
        ),
      ),
    );
  }
}
