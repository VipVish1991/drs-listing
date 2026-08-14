import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../models/appointment_model.dart';
import '../services/meet_service.dart';
import '../utils/snackbar_helpers.dart';

/// Shared "Video Consultation" bottom sheet for the free Google Meet
/// integration (launcher + share — no API keys).
///
/// Shows the appointment's saved meeting link (or a prompt to create one)
/// and offers:
///   * **Join Video Call** — opens the saved link in the browser/Meet app
///   * **Start New Meeting** — opens `meet.new` so Google generates a real
///     link, then prompts to paste it back
///   * **Enter / Paste Link** — manual entry with a clipboard shortcut
///   * **Copy Link** / **Send Link** (WhatsApp / SMS to the other party)
///
/// Only REAL Google-generated links are ever stored ([MeetService.normalize]
/// validates the code format) — Google rejects made-up Meet codes, so the
/// app never invents one.
///
/// Persistence is delegated to the caller via [onSaveLink] (the patient or
/// doctor controller's `saveMeetLink`), which also updates the reactive
/// appointment list in place.
class VideoCallSheet extends StatefulWidget {
  final AppointmentModel appointment;

  /// The OTHER party's mobile number — where "Send Link" delivers the
  /// invite. Patient side: the doctor's number; doctor side: the patient's
  /// number. Null/empty hides the share action.
  final String? sharePhone;

  /// Label for the other party ("Send Link to Patient" vs "Doctor").
  final String otherPartyLabel;

  /// Persists the link; returns `true` only when the write landed.
  final Future<bool> Function(String? link) onSaveLink;

  const VideoCallSheet({
    super.key,
    required this.appointment,
    this.sharePhone,
    this.otherPartyLabel = 'the other party',
    required this.onSaveLink,
  });

  /// Opens the sheet as a modal bottom sheet.
  static void show({
    required AppointmentModel appointment,
    String? sharePhone,
    bool isDoctor = false,
    required Future<bool> Function(String? link) onSaveLink,
  }) {
    Get.bottomSheet(
      VideoCallSheet(
        appointment: appointment,
        sharePhone: sharePhone,
        otherPartyLabel: isDoctor ? 'Patient' : 'Doctor',
        onSaveLink: onSaveLink,
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  @override
  State<VideoCallSheet> createState() => _VideoCallSheetState();
}

class _VideoCallSheetState extends State<VideoCallSheet> {
  /// The current link for this appointment — seeded from the model so a
  /// freshly-saved link survives the sheet staying open.
  late String? _link;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _link = widget.appointment.meetLink;
  }

  String? get _code => _link == null ? null : MeetService.codeOf(_link!);

  // ── Actions ────────────────────────────────────────────────────

  Future<void> _startMeeting() async {
    await MeetService.startNewMeeting();
    if (!mounted) return;
    showSuccessSnackbar(
      'Meeting started in Google Meet — copy the link there, '
      'then paste it below',
    );
    _promptPasteLink();
  }

  /// Opens a dialog asking for the meeting link, with a clipboard shortcut
  /// (the user just copied it from meet.new).
  Future<void> _promptPasteLink() async {
    final controller = TextEditingController(text: _link ?? '');
    final saved = await Get.dialog<String?>(
      _PasteLinkDialog(controller: controller),
      barrierDismissible: true,
    );
    if (saved == null || !mounted) return;
    await _save(saved);
  }

  Future<void> _save(String raw) async {
    final url = MeetService.normalize(raw);
    if (url == null) {
      showErrorSnackbar(
        'That does not look like a Google Meet link. '
        'It should look like https://meet.google.com/abc-defg-hij',
      );
      return;
    }
    setState(() => _saving = true);
    final ok = await widget.onSaveLink(url);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      setState(() => _link = url);
      showSuccessSnackbar('Meeting link saved');
    } else {
      showErrorSnackbar('Could not save the link. Please try again.');
    }
  }

  Future<void> _join() async {
    final link = _link;
    if (link == null) return;
    await MeetService.openMeeting(link);
  }

  Future<void> _copy() async {
    final link = _link;
    if (link == null) return;
    await MeetService.copyLink(link);
  }

  Future<void> _share() async {
    final link = _link;
    if (link == null || (widget.sharePhone ?? '').isEmpty) return;
    final choice = await Get.bottomSheet<String>(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        decoration: const BoxDecoration(
          color: AppColors.bgMain,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textCaption.withAlpha(90),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Send meeting link',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textHeading,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'To ${widget.otherPartyLabel}: ${widget.sharePhone}',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textCaption,
              ),
            ),
            const SizedBox(height: 18),
            _ShareOption(
              key: const ValueKey('video_call_share_whatsapp'),
              icon: Icons.chat_rounded,
              color: const Color(0xFF25D366),
              label: 'WhatsApp',
              onTap: () => Get.back(result: 'whatsapp'),
            ),
            const SizedBox(height: 10),
            _ShareOption(
              key: const ValueKey('video_call_share_sms'),
              icon: Icons.sms_rounded,
              color: AppColors.info,
              label: 'SMS',
              onTap: () => Get.back(result: 'sms'),
            ),
          ],
        ),
      ),
      backgroundColor: Colors.transparent,
    );
    if (choice == null || !mounted) return;
    if (choice == 'whatsapp') {
      await MeetService.shareViaWhatsApp(widget.sharePhone, link);
    } else {
      await MeetService.shareViaSms(widget.sharePhone, link);
    }
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasLink = _link != null;
    final canShare = hasLink && (widget.sharePhone ?? '').isNotEmpty;

    return Container(
      key: const ValueKey('video_call_sheet'),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      decoration: const BoxDecoration(
        color: AppColors.bgMain,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textCaption.withAlpha(90),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            // ── Header ──
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.info.withAlpha(18),
                    border: Border.all(
                      color: AppColors.info.withAlpha(50),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.videocam_rounded,
                    size: 24,
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Video Consultation',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textHeading,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Google Meet — free video call',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textCaption,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Get.back(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.textCaption.withAlpha(15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textCaption,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // ── Status card ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (hasLink ? AppColors.success : AppColors.warning)
                    .withAlpha(10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (hasLink ? AppColors.success : AppColors.warning)
                      .withAlpha(40),
                ),
              ),
              child: hasLink
                  ? Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Meeting link ready',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textHeading,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _code ?? _link!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textCaption,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'No meeting link yet. Start a Google Meet call, '
                            'then paste the link here so both of you join '
                            'the same meeting.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppColors.textBody,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            // ── Actions ──
            if (hasLink) ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  key: const ValueKey('video_call_join'),
                  onPressed: _saving ? null : _join,
                  icon: const Icon(Icons.videocam_rounded, size: 18),
                  label: const Text(
                    'Join Video Call',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.info,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                key: const ValueKey('video_call_start'),
                onPressed: _saving ? null : _startMeeting,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'Start New Meeting',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                key: const ValueKey('video_call_paste'),
                onPressed: _saving ? null : _promptPasteLink,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: Text(
                  hasLink ? 'Change Meeting Link' : 'Enter / Paste Link',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary.withAlpha(60)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            if (hasLink) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        key: const ValueKey('video_call_copy'),
                        onPressed: _saving ? null : _copy,
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text(
                          'Copy Link',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textHeading,
                          side: BorderSide(
                            color: AppColors.textCaption.withAlpha(50),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (canShare) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton.icon(
                          key: const ValueKey('video_call_share'),
                          onPressed: _saving ? null : _share,
                          icon: const Icon(Icons.send_rounded, size: 16),
                          label: Text(
                            'Send to ${widget.otherPartyLabel}',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.success,
                            side: BorderSide(
                              color: AppColors.success.withAlpha(50),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 14),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppColors.textCaption,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Google Meet is free. The person who starts the meeting '
                    'creates the link; anyone with it can join — no Google '
                    'account needed for guests.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppColors.textCaption,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog asking for the meeting link — text field with a "Paste from
/// clipboard" shortcut (the user just copied it from meet.new).
class _PasteLinkDialog extends StatefulWidget {
  final TextEditingController controller;

  const _PasteLinkDialog({required this.controller});

  @override
  State<_PasteLinkDialog> createState() => _PasteLinkDialogState();
}

class _PasteLinkDialogState extends State<_PasteLinkDialog> {
  bool _pasting = false;

  Future<void> _pasteFromClipboard() async {
    setState(() => _pasting = true);
    final text = await MeetService.clipboardText();
    if (!mounted) return;
    setState(() {
      _pasting = false;
      if (text != null) widget.controller.text = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Meeting Link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste the Google Meet link from the meeting you started '
            '(e.g. https://meet.google.com/abc-defg-hij).',
            style: TextStyle(fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('meet_link_field'),
            controller: widget.controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'https://meet.google.com/…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('meet_link_paste'),
              onPressed: _pasting ? null : _pasteFromClipboard,
              icon: _pasting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.content_paste_rounded, size: 16),
              label: const Text('Paste from clipboard'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: null),
          child: Text('Cancel', style: TextStyle(color: AppColors.textCaption)),
        ),
        ElevatedButton(
          key: const ValueKey('meet_link_save'),
          onPressed: () => Get.back(result: widget.controller.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Save Link'),
        ),
      ],
    );
  }
}

/// One share-method option (WhatsApp / SMS) in the share picker.
class _ShareOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ShareOption({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(15),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textHeading,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textCaption.withAlpha(150),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
