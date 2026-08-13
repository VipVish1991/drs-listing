import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../controllers/home_controller.dart';
import '../../controllers/voice_controller.dart';
import '../../services/local_storage_service.dart';
import '../../services/tts_service.dart';
import '../../controllers/notification_center_controller.dart';
import '../../widgets/health_assistant_video.dart';
import '../../widgets/voice_button.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/category_filter_sheet.dart';
import '../../widgets/connectivity_status_card.dart';
import '../../widgets/notification_bell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final HomeController _homeController = Get.find<HomeController>();
  final VoiceController _voiceController = Get.find<VoiceController>();
  final ScrollController _chatScrollController = ScrollController();

  /// Whether the welcome flow (video greeting TTS → auto-start mic) has
  /// already run for the current empty-chat session. Reset whenever the
  /// chat is cleared so the greeting replays.
  bool _welcomeSpoken = false;

  /// Whether the patient last left the avatar video paused. Restored from
  /// local storage when the screen opens so a paused avatar stays paused
  /// on the next launch; updated + persisted whenever the video is paused
  /// or resumed (by tap, or by the welcome-flow playback stopping).
  bool _avatarVideoPaused = false;

  /// True while the welcome is active — the avatar video is playing and
  /// the TTS greeting is being spoken (video first, voice a beat later).
  /// Drives the avatar's autoplay + speaking animation (breathing pulse).
  bool _welcomeActive = false;

  /// One-shot timer that starts the first welcome: on a fresh open the
  /// avatar video kicks in after [_welcomeStartDelay], with the greeting
  /// audio starting together with it ([AppConstants.welcomeGreetingAudioDelay]
  /// — "With the video"). Cancelled as soon as the user starts
  /// interacting (or the widget is disposed).
  Timer? _welcomeTimer;

  /// One-shot timer for the greeting audio — it starts together with the
  /// video ("With the video", the only preset — [AppConstants
  /// .welcomeGreetingAudioDelay]). Kept so the greeting can still be
  /// cancelled if the user starts interacting mid-welcome. Cancelled
  /// alongside the welcome timer.
  Timer? _greetingAudioTimer;

  /// How long a freshly-opened home screen waits before the avatar video
  /// kicks in (patient side, first open).
  static const Duration _welcomeStartDelay = Duration(milliseconds: 1500);

  /// Tracks the messages subscription so it can be cancelled on dispose.
  StreamSubscription? _messagesSub;

  /// Tracks the speech-engine readiness subscription so it can be
  /// cancelled on dispose.
  StreamSubscription? _micInitSub;

  /// Set when a greeting has finished but the speech engine wasn't ready
  /// yet (its init is deferred to the dashboard and the mic-permission
  /// prompt may still be open). The [isInitialized] listener below then
  /// starts the mic the moment the engine flips ready — so the mic
  /// auto-starts right after ALL permissions are allowed, not only when
  /// the greeting happens to line up with a warm engine.
  bool _micPendingAfterGreeting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Restore the avatar-video pause state saved on a previous session
    // (paused → the welcome stays quiet until the patient taps the video).
    _avatarVideoPaused = LocalStorageService().isAvatarVideoPaused();

    // Load the notification badge when the home screen appears (covers
    // pushes received while away, and the initial load after login).
    NotificationCenterController.instance.load();

    // The patient is now logged in and on the dashboard — this is the
    // right moment to ask for permissions and warm up the speech engine.
    // The prompts run SEQUENTIALLY, one at a time: the location (GPS)
    // permission first (driven by HomeController's dialog), and only
    // after that flow resolves does the microphone permission get asked
    // (voice assistant) and the speech engine warm up. The avatar welcome
    // (video + greeting audio) then starts, so the greeting never speaks
    // over a prompt; when it finishes, the mic auto-starts (see
    // [_autoStartMicAfterGreeting]). Every step is fire-and-forget — a
    // denied prompt never blocks the home screen.
    _runPermissionSequencedSetup();

    // When the chat is cleared (delete button) the empty state returns —
    // reset the flag so the greeting + auto-mic welcome replays. The
    // moment a real conversation starts (first message lands), the
    // greeting voiceover is no longer relevant, so stop it immediately.
    _messagesSub = _voiceController.messages.listen((messages) {
      if (messages.isEmpty) {
        _welcomeSpoken = false;
      } else {
        // A real conversation has started — the delayed greeting must not
        // speak over it.
        _welcomeTimer?.cancel();
        _stopGreetingAudio();
      }
    });

    // Fire the parked mic auto-start the moment the speech engine becomes
    // ready (a greeting completed while the engine was still warming up /
    // the mic-permission prompt was still open). Guards re-checked inside
    // [_autoStartMicAfterGreeting], so a user who already started talking
    // is never spoken over.
    _micInitSub = _voiceController.isInitialized.listen((ready) {
      if (ready && _micPendingAfterGreeting && mounted) {
        _micPendingAfterGreeting = false;
        _autoStartMicAfterGreeting();
      }
    });
  }

  /// Chains the post-login setup off the location-permission flow, so the
  /// OS permission prompts never overlap:
  ///
  ///   1. GPS permission — HomeController's dialog (awaiting
  ///      [HomeController.locationPermissionFlowDone] covers both the
  ///      "already granted" and the "user just answered the dialog"
  ///      cases).
  ///   2. Microphone permission — the explicit request below, plus the
  ///      speech-engine warmup which surfaces the OS mic prompt on
  ///      Android. Awaiting the request means the avatar welcome below
  ///      never starts (and its greeting never speaks) while a prompt is
  ///      still on screen.
  ///   3. Avatar welcome — video + greeting audio play together; when
  ///      they finish, the mic auto-starts (see [_autoStartMicAfterGreeting]).
  Future<void> _runPermissionSequencedSetup() async {
    await _homeController.whenLocationPermissionFlowDone();
    if (!mounted) return;
    await _requestMicPermission();
    if (!mounted) return;
    // Warm up the speech engine (fire-and-forget: an engine that isn't
    // ready yet never blocks the screen — the auto-mic parks until it is).
    _voiceController.initSpeech();
    _scheduleWelcomeFlow();
  }

  /// Starts the first welcome: wait [_welcomeStartDelay] before the
  /// avatar video kicks in (patient-side first open); the greeting audio
  /// follows together with it. Called once the permission flow has
  /// resolved so the video never plays behind a prompt. One-shot —
  /// cancelled as soon as the user starts interacting (or the widget is
  /// disposed).
  void _scheduleWelcomeFlow() {
    if (!mounted) return;
    _welcomeTimer?.cancel();
    _welcomeTimer = Timer(_welcomeStartDelay, () {
      if (mounted) _maybeRunWelcomeFlow();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A push delivered while the app was backgrounded isn't surfaced by
    // onMessage — refresh the notification badge on resume so it's current.
    if (state == AppLifecycleState.resumed) {
      NotificationCenterController.instance.load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _welcomeTimer?.cancel();
    _greetingAudioTimer?.cancel();
    _messagesSub?.cancel();
    _micInitSub?.cancel();
    TtsService.instance.stop();
    _chatScrollController.dispose();
    super.dispose();
  }

  /// Starts the avatar video, then speaks the Hinglish greeting after a
  /// short delay (the video plays first, the voice follows), and finally
  /// auto-starts the mic so the user can immediately describe their
  /// symptoms. When they stop speaking the existing voice pipeline
  /// analyzes the symptoms and shows results.
  void _maybeRunWelcomeFlow() {
    // The patient can turn the automatic welcome off from Profile →
    // Auto-Play Welcome — then the avatar stays paused until they tap
    // it (tapping still plays the video + greeting manually).
    if (!LocalStorageService().isWelcomeAutoPlayEnabled()) return;
    if (_welcomeSpoken) return;
    if (_voiceController.messages.isNotEmpty) return;
    // Only greet while the home screen is actually on top — a route pushed
    // within the welcome window (e.g. a quick chip → doctor search) must
    // not get an unprompted voiceover.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    // If the user has already started talking (mic on / processing), never
    // speak the greeting over them — the flow just stays quiet this session.
    if (_voiceController.isListening.value ||
        _voiceController.isRecordingAudio.value ||
        _voiceController.isProcessing.value) {
      return;
    }
    // If the patient paused the avatar video, the whole welcome (video +
    // greeting audio + auto-mic) stays quiet on this open — the avatar
    // just sits paused until they tap it to play.
    if (_avatarVideoPaused) return;
    _welcomeSpoken = true;
    // Start the avatar video now; the greeting audio starts with it
    // ([AppConstants.welcomeGreetingAudioDelay] — "With the video").
    setState(() => _welcomeActive = true);
    _scheduleGreetingAudio(
      onComplete: () {
        if (mounted) setState(() => _welcomeActive = false);
        // The greeting-driven playback has finished — the avatar video
        // stops on its own now, and the mic auto-starts so the patient
        // can describe their symptoms right away. The avatar is NOT
        // marked as paused: the welcome (video + greeting) replays on
        // the next app open, and the mic starts after it again — every
        // time the video + audio complete.
        _autoStartMicAfterGreeting();
      },
    );
  }

  /// Schedules the Hinglish greeting to start with the avatar video
  /// ("With the video" — [LocalStorageService.getWelcomeGreetingDelayMs]
  /// resolves to [AppConstants.welcomeGreetingAudioDelay]), then runs
  /// [onComplete] when it finishes. Shared by the auto-welcome flow and
  /// the avatar tap-to-resume path, so both stay on the same beat.
  /// Cancelled if the user starts interacting (via [_stopGreetingAudio])
  /// or the widget is disposed.
  void _scheduleGreetingAudio({required VoidCallback onComplete}) {
    _greetingAudioTimer?.cancel();
    _greetingAudioTimer = Timer(
      Duration(milliseconds: LocalStorageService().getWelcomeGreetingDelayMs()),
      () => _speakGreeting(onComplete: onComplete),
    );
  }

  /// Speaks the Hinglish greeting, then runs [onComplete] when it
  /// finishes.
  ///
  /// Scheduled to start together with the avatar video
  /// ([AppConstants.welcomeGreetingAudioDelay]). The user may have
  /// started talking or navigated away in the meantime, so the same
  /// guards as
  /// [_maybeRunWelcomeFlow] are re-checked here — the greeting never
  /// speaks over an active conversation. If the guards fail, the welcome
  /// ends quietly (video stops) instead of looping with no speech
  /// scheduled.
  void _speakGreeting({required VoidCallback onComplete}) {
    if (!mounted) return;
    // The patient may have turned the auto-welcome off (Profile →
    // Auto-Play Welcome) while the video was playing, or started talking,
    // or navigated away — in every case the greeting ends quietly (video
    // stops) instead of speaking.
    if (!LocalStorageService().isWelcomeAutoPlayEnabled() ||
        _voiceController.messages.isNotEmpty ||
        _voiceController.isListening.value ||
        _voiceController.isRecordingAudio.value ||
        _voiceController.isProcessing.value ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      setState(() => _welcomeActive = false);
      return;
    }
    TtsService.instance.speakGreeting(onComplete: onComplete);
  }

  /// Immediately halts any pending/still-speaking greeting + speaking
  /// animation. Called once a chat message exists (text or voice), so
  /// the assistant never keeps talking over an active conversation.
  ///
  /// A conversation starting does NOT mark the avatar as paused — only a
  /// deliberate tap-to-pause does (see [_handleAvatarPlaybackChanged]) —
  /// so the greeting can replay once the conversation ends (chat cleared)
  /// and on the next app open.
  void _stopGreetingAudio() {
    _greetingAudioTimer?.cancel();
    TtsService.instance.stop();
    if (_welcomeActive && mounted) {
      setState(() => _welcomeActive = false);
    }
  }

  /// Tapping the avatar video to pause it acts as a single "stop
  /// everything" gesture — also stops the TTS greeting speech and, if
  /// the mic is currently listening/recording, stops that too.
  void _stopEverything() {
    _stopGreetingAudio();
    if (_voiceController.isListening.value ||
        _voiceController.isRecordingAudio.value) {
      _voiceController.stopListening();
    }
  }

  /// Wired to the avatar video's `onPlayingChanged` — tapping the video
  /// toggles speech in lockstep with it: pausing the video stops the
  /// greeting speech (and the mic), and resuming the video replays the
  /// greeting speech the same way as the auto-welcome ("With the
  /// video" — the voice starts together with the video). (True
  /// pause-and-continue for TTS isn't reliably available, so
  /// "resume" re-speaks the greeting rather than continuing
  /// mid-sentence.) Every toggle is persisted to local storage so the
  /// next app open restores the same state.
  void _handleAvatarPlaybackChanged(bool playing) {
    _setAvatarVideoPaused(!playing);
    if (playing) {
      setState(() => _welcomeActive = true);
      _scheduleGreetingAudio(
        onComplete: () {
          if (mounted) setState(() => _welcomeActive = false);
          // Every greeting completion — including a manual tap-to-resume
          // replay — auto-starts the mic, exactly like the first
          // auto-welcome.
          _autoStartMicAfterGreeting();
        },
      );
    } else {
      _stopEverything();
    }
  }

  /// Asks for the microphone permission (used by the voice assistant)
  /// right after the patient lands on the dashboard. Best-effort: on a
  /// platform without the plugin (tests / desktop) this silently no-ops.
  /// When denied, a hint points the user to Settings (permanently denied
  /// permissions can only be restored there).
  Future<void> _requestMicPermission() async {
    PermissionStatus status;
    try {
      // Already granted (OS won't re-prompt) — nothing to ask for.
      if (await Permission.microphone.status.isGranted) return;
      status = await Permission.microphone.request();
    } catch (_) {
      // Plugin unavailable (tests / desktop) — nothing to ask for.
      return;
    }
    if (!mounted) return;
    if (status.isDenied || status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status.isPermanentlyDenied
                ? 'Microphone permission is off — enable it in Settings '
                      'to use voice input.'
                : 'Microphone permission is needed for voice input.',
          ),
          behavior: SnackBarBehavior.floating,
          action: status.isPermanentlyDenied
              ? SnackBarAction(label: 'Settings', onPressed: openAppSettings)
              : SnackBarAction(
                  label: 'Allow',
                  onPressed: () => _requestMicPermission(),
                ),
        ),
      );
    }
  }

  /// Persists the avatar-video pause state so the next app open restores
  /// it — a paused avatar stays paused, a playing one auto-plays again
  /// after the welcome delay. (shared_preferences → localStorage on the
  /// web build.)
  void _setAvatarVideoPaused(bool paused) {
    _avatarVideoPaused = paused;
    LocalStorageService().setAvatarVideoPaused(paused);
  }

  /// Called when the spoken greeting finishes. Auto-starts the mic so the
  /// user can immediately describe their symptoms.
  ///
  /// Runs on EVERY greeting completion — the first auto-welcome, a manual
  /// tap-to-resume replay, and the clear-chat replay. When the speech
  /// engine isn't ready yet (its init is deferred to the dashboard, and
  /// the mic-permission prompt may still be on screen), the auto-start is
  /// PARKED — the [isInitialized] listener fires it the moment the engine
  /// flips ready, so the mic starts right after all permissions are
  /// allowed. In tests the engine is never initialized, so nothing
  /// happens and the flow stays deterministic.
  void _autoStartMicAfterGreeting() {
    final vc = _voiceController;
    if (!mounted) return;
    // Only start the mic while the home screen is actually on top — the
    // parked listener can fire well after the greeting (once the engine
    // finishes initializing / permission is granted), by which time the
    // user may have navigated away. Never start recording on a screen
    // they aren't looking at (same guard as [_speakGreeting]).
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) {
      _micPendingAfterGreeting = false;
      return;
    }
    if (vc.messages.isNotEmpty) return;
    if (vc.isListening.value ||
        vc.isProcessing.value ||
        vc.isRecordingAudio.value) {
      _micPendingAfterGreeting = false;
      return;
    }
    if (!vc.isInitialized.value) {
      // Park the auto-start until the engine (and its permission prompt)
      // finishes initializing.
      _micPendingAfterGreeting = true;
      return;
    }
    _micPendingAfterGreeting = false;
    vc.startListening();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;
    final captionColor = isDark
        ? const Color(0xFF999999)
        : AppColors.textCaption;

    return Scaffold(
      backgroundColor: Color(0xFFFEFAF9),
      body: SafeArea(
        child: Obx(() {
          // While listening, a tap anywhere on the screen stops the mic —
          // not just the mic button itself — so stopping a recording is
          // always one easy tap away.
          final listening =
              _voiceController.isListening.value ||
              _voiceController.isRecordingAudio.value;
          return Stack(
            children: [
              Column(
                children: [
                  // Header (no person icon)
                  _buildHeader(context, textColor, captionColor, isDark),

                  // Connectivity status card — appears while offline and
                  // shows the connected Wi-Fi network + signal strength.
                  // Hidden (zero-height) when online.
                  const ConnectivityStatusCard(),

                  // Chat Area
                  Expanded(
                    child: _buildChatArea(
                      context,
                      textColor,
                      bodyColor,
                      captionColor,
                      isDark,
                      _chatScrollController,
                    ),
                  ),

                  // Voice Controls
                  _buildVoiceControls(context, textColor, captionColor, isDark),
                ],
              ),
              if (listening)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _voiceController.stopListening(),
                    child: const ColoredBox(color: Colors.transparent),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Color textColor,
    Color captionColor,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withAlpha(isDark ? 18 : 12),
            AppColors.bgMain.withAlpha(0),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Soft gradient status badge — a quiet signature element that
          // echoes the assistant avatar's glow used in the empty state.
          Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withAlpha(60),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.health_and_safety_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              )
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                      'Hello, ${_homeController.userName}!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: textColor,
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .slideX(
                      begin: -0.05,
                      end: 0,
                      duration: 400.ms,
                      curve: Curves.easeOut,
                    ),
                const SizedBox(height: 4),
                // GPS Location - real location from device
                Obx(() {
                  if (_homeController.isLoadingLocation.value) {
                    return const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Getting location...',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textCaption,
                          ),
                        ),
                      ],
                    );
                  }
                  final location = _homeController.currentLocation.value;
                  final isDefault =
                      location == AppConstants.defaultLocation ||
                      location == 'Location unavailable';
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 14,
                        color: AppColors.textCaption,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textCaption,
                          ),
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () =>
                              _homeController.requestLocationPermission(),
                          child: const Icon(
                            Icons.gps_fixed_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
                        ),
                      ] else
                        GestureDetector(
                          onTap: () => _homeController.refreshLocation(),
                          child: const Icon(
                            Icons.refresh_rounded,
                            size: 14,
                            color: AppColors.textCaption,
                          ),
                        ),
                    ],
                  );
                }),
              ],
            ),
          ),
          // Notification bell — badge shows the unread push count; tap opens
          // the in-app notification center.
          NotificationBell(
            backgroundColor: isDark
                ? Colors.white.withAlpha(20)
                : AppColors.primary.withAlpha(16),
            borderColor: isDark
                ? Colors.white.withAlpha(30)
                : AppColors.primary.withAlpha(30),
            iconColor: isDark ? Colors.white : AppColors.primary,
            badgeBorderColor: isDark ? const Color(0xFF15151F) : Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildChatArea(
    BuildContext context,
    Color textColor,
    Color bodyColor,
    Color captionColor,
    bool isDark,
    ScrollController scrollController,
  ) {
    return RefreshIndicator(
      onRefresh: () => _homeController.refreshLocation(),
      color: AppColors.primary,
      displacement: 40,
      child: Obx(() {
        final messages = _voiceController.messages;

        if (messages.isEmpty) {
          return _buildEmptyState(
            context,
            textColor,
            bodyColor,
            captionColor,
            isDark,
          );
        }

        // Auto-scroll to the latest message after each update
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {
            scrollController.animateTo(
              scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });

        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(vertical: 16),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount:
              messages.length + (_voiceController.isProcessing.value ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == messages.length) {
              return _buildTypingIndicator(isDark);
            }
            return ChatBubble(message: messages[index]);
          },
        );
      }),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    Color textColor,
    Color bodyColor,
    Color captionColor,
    bool isDark,
  ) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Transform.translate(
        offset: const Offset(0, -16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Welcome video (health assistant intro) — no card or shadow
            // behind it, background stays fully transparent. The
            // "speaking" cue is motion only: a subtle breathing scale
            // while the TTS greeting plays. No entrance fade/scale here —
            // it just appears at its resting size. Falls back to a
            // placeholder icon when the video can't load (e.g. tests).
            AnimatedScale(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              scale: _welcomeActive ? 1.05 : 1.0,
              child: HealthAssistantVideo(
                // The avatar video stays paused until the welcome flow
                // actually starts (1.5s after the screen opens) — then it
                // autoplays, with the greeting voice following after the
                // patient's chosen stagger (Profile → Auto-Play Welcome).
                // If the patient paused it last session (localStorage), it
                // stays paused and only starts after they tap to play.
                autoPlay: _welcomeActive && !_avatarVideoPaused,
                onPlayingChanged: _handleAvatarPlaybackChanged,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'How can I help you today?',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: textColor,
              ),
            ).animate().fadeIn(duration: 500.ms, delay: 100.ms),
            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Tap the mic and describe your symptoms\nin any Indian language',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: bodyColor, // Full opacity - fixed visibility
                  height: 1.5,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Quick recommendations - removed Skin Care card
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                _QuickChip(
                  icon: Icons.thermostat_rounded,
                  label: 'Fever & Cold',
                  color: AppColors.healthImmune,
                  isDark: isDark,
                  onTap: () =>
                      _homeController.searchDoctors('General Physician'),
                ),
                _QuickChip(
                  icon: Icons.favorite_rounded,
                  label: 'Chest Pain',
                  color: AppColors.healthHeart,
                  isDark: isDark,
                  onTap: () => _homeController.searchDoctors('Cardiologist'),
                ),
                _QuickChip(
                  icon: Icons.bakery_dining_rounded,
                  label: 'Stomach Pain',
                  color: AppColors.healthDigestive,
                  isDark: isDark,
                  onTap: () =>
                      _homeController.searchDoctors('Gastroenterologist'),
                ),
                _QuickChip(
                  icon: Icons.psychology_rounded,
                  label: 'Headache',
                  color: AppColors.healthBrain,
                  isDark: isDark,
                  onTap: () => _homeController.searchDoctors('Neurologist'),
                ),
              ],
            ).animate().fadeIn(duration: 500.ms, delay: 220.ms),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withAlpha(40),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.health_and_safety,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A2E) : AppColors.bgCard,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (index) =>
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withAlpha(
                          (100 + (index * 50)).clamp(0, 255),
                        ),
                      ),
                    ).animate().fadeIn(
                      duration: 400.ms,
                      delay: Duration(milliseconds: index * 200),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the category filter bottom sheet and navigates to doctor
  /// search when the user selects a category.
  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CategoryFilterSheet(
        onSelect: (category) {
          _homeController.searchDoctors(category);
        },
      ),
    );
  }

  Widget _buildVoiceControls(
    BuildContext context,
    Color textColor,
    Color captionColor,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15151F) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 0 : 6),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          // AI Response suggestion / Find Specialist card
          Obx(() {
            final analysis = _voiceController.latestAnalysis.value;
            if (analysis != null) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassCard(
                  padding: const EdgeInsets.all(12),
                  borderRadius: 16,
                  onTap: () =>
                      _homeController.searchDoctors(analysis.specialist),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: AppColors.success.withAlpha(30),
                        ),
                        child: const Icon(
                          Icons.search_rounded,
                          color: AppColors.success,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Find ${analysis.specialist}s near you',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tap to search nearby clinics & hospitals',
                              style: TextStyle(
                                fontSize: 12,
                                color: captionColor.withAlpha(200),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: AppColors.textCaption,
                      ),
                    ],
                  ),
                ),
              );
            }
            return const SizedBox();
          }),

          // Voice button row: [filter] — [mic] — [delete]
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Filter icon (left side) — opens category filter sheet
              _RoundIconButton(
                icon: Icons.tune_rounded,
                color: captionColor,
                isDark: isDark,
                onTap: () => _showFilterSheet(context),
              ),

              const SizedBox(width: 22),

              // Main voice button — starts/stops listening inline
              GestureDetector(
                onTap: () {
                  if (_voiceController.isListening.value) {
                    _voiceController.stopListening();
                  } else {
                    _voiceController.startListening();
                  }
                },
                child: Obx(
                  () => Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withAlpha(
                            _voiceController.isListening.value ? 70 : 35,
                          ),
                          blurRadius: _voiceController.isListening.value
                              ? 26
                              : 16,
                          spreadRadius: _voiceController.isListening.value
                              ? 2
                              : 0,
                        ),
                      ],
                    ),
                    child: VoiceButton(
                      isListening:
                          _voiceController.isListening.value ||
                          _voiceController.isRecordingAudio.value,
                      isProcessing:
                          _voiceController.isProcessing.value ||
                          _voiceController.isTranscribing.value,
                      onPressed: () => _voiceController.startListening(),
                      onStopPressed: () => _voiceController.stopListening(),
                      size: 72,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 22),

              // Delete button (right side — always visible)
              _RoundIconButton(
                icon: Icons.delete_outline_rounded,
                color: captionColor,
                isDark: isDark,
                onTap: () {
                  _voiceController.clearChat();
                  // Replay the greeting + auto-mic welcome after clearing.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _maybeRunWelcomeFlow();
                  });
                },
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Status text
          Obx(() {
            if (_voiceController.isListening.value) {
              return const Text(
                'Listening... Tap again to stop',
                style: TextStyle(fontSize: 12, color: AppColors.textCaption),
              );
            }
            if (_voiceController.isProcessing.value) {
              return const Text(
                'Analyzing your symptoms...',
                style: TextStyle(fontSize: 12, color: AppColors.textCaption),
              );
            }
            if (_voiceController.currentText.value.isNotEmpty) {
              return Text(
                '\u201c${_voiceController.currentText.value}\u201d',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textCaption,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              );
            }
            return const Text(
              'Tap the mic to describe your symptoms',
              style: TextStyle(fontSize: 12, color: AppColors.textCaption),
            );
          }),
        ],
      ),
    );
  }
}

/// Round icon button used for the filter/delete controls flanking the
/// mic — shared so both stay visually identical and get a consistent
/// press feedback.
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.icon,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(15),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _QuickChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(isDark ? 40 : 26),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withAlpha(isDark ? 70 : 45),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? color : color.withAlpha(220),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
