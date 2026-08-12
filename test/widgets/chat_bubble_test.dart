import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/widgets/chat_bubble.dart';
import '../helpers/test_data.dart';

/// Wraps a [ChatBubble] in a themed [MaterialApp] + [Scaffold] so the
/// widget can resolve Theme and MediaQuery correctly.
Widget _buildBubble(ChatBubble bubble) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: SingleChildScrollView(child: bubble)),
  );
}

void main() {
  // Load dotenv with a placeholder so AppConstants.googleMapsApiKey
  // doesn't throw NotInitializedError during widget builds.
  setUpAll(() {
    dotenv.loadFromString(envString: 'GOOGLE_MAPS_API_KEY=');
  });
  group('ChatBubble', () {
    // ── User message ───────────────────────────────────────────────

    testWidgets('renders user message text', (tester) async {
      await tester.pumpWidget(
        _buildBubble(
          ChatBubble(message: chatMessageUser(text: 'I have a fever')),
        ),
      );
      // Pump past the entrance animation
      await tester.pumpAndSettle();

      expect(find.text('I have a fever'), findsOneWidget);
    });

    testWidgets('shows person icon for user avatar', (tester) async {
      await tester.pumpWidget(
        _buildBubble(ChatBubble(message: chatMessageUser(text: 'Hello'))),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('does not show AI avatar for user messages', (tester) async {
      await tester.pumpWidget(
        _buildBubble(ChatBubble(message: chatMessageUser(text: 'Hi'))),
      );
      await tester.pumpAndSettle();

      // AI avatar uses Image.asset — no Image should be present on user bubbles
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('does not show analysis badge for user messages', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildBubble(ChatBubble(message: chatMessageUser(text: 'I am sick'))),
      );
      await tester.pumpAndSettle();

      // No medical_services icon (analysis badge) for user messages
      expect(find.byIcon(Icons.medical_services), findsNothing);
    });

    testWidgets('does not show specialist finder for user messages', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildBubble(
          ChatBubble(
            message: chatMessageUser(text: 'Check this'),
            onTapSpecialist: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // User messages never show the specialist finder
      expect(find.textContaining('Find'), findsNothing);
    });

    // ── AI message (no analysis) ────────────────────────────────────

    testWidgets('renders AI message text', (tester) async {
      await tester.pumpWidget(
        _buildBubble(
          ChatBubble(message: chatMessageAi(text: 'You may have a cold')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You may have a cold'), findsOneWidget);
    });

    testWidgets('shows image widget for AI avatar', (tester) async {
      await tester.pumpWidget(
        _buildBubble(ChatBubble(message: chatMessageAi(text: 'Response'))),
      );
      await tester.pumpAndSettle();

      // The AI avatar uses Image.asset('assets/images/app_logo.png'),
      // not an icon — verify that an Image widget is present on AI bubbles.
      expect(find.byType(Image), findsAtLeast(1));
    });

    testWidgets('does not show person icon for AI messages', (tester) async {
      await tester.pumpWidget(
        _buildBubble(ChatBubble(message: chatMessageAi(text: 'Response'))),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person), findsNothing);
    });

    // ── AI message with analysis ────────────────────────────────────

    testWidgets('shows specialist badge when analysis is present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildBubble(
          ChatBubble(
            message: chatMessageAi(
              text: 'You should see a cardiologist.',
              analysis: analysisCardiologist(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cardiologist'), findsOneWidget);
      // Badge icon
      expect(find.byIcon(Icons.medical_services), findsOneWidget);
    });

    testWidgets('does not show specialist badge without analysis', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildBubble(ChatBubble(message: chatMessageAi(text: 'Rest well'))),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.medical_services), findsNothing);
    });

    // ── Specialist search suggestion ────────────────────────────────

    testWidgets(
      'shows "Find [specialist]s near you" when onTapSpecialist is set',
      (tester) async {
        await tester.pumpWidget(
          _buildBubble(
            ChatBubble(
              message: chatMessageAi(
                text: 'You need a cardiologist.',
                analysis: analysisCardiologist(),
              ),
              onTapSpecialist: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Find Cardiologists near you'), findsOneWidget);
      },
    );

    testWidgets('tapping specialist suggestion calls callback', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _buildBubble(
          ChatBubble(
            message: chatMessageAi(
              text: 'See a neurologist.',
              analysis: analysisNeurologist(),
            ),
            onTapSpecialist: () => tapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Find Neurologists near you'));
      expect(tapped, isTrue);
    });

    testWidgets(
      'does not show specialist finder when onTapSpecialist is null',
      (tester) async {
        await tester.pumpWidget(
          _buildBubble(
            ChatBubble(
              message: chatMessageAi(
                text: 'See a cardiologist.',
                analysis: analysisCardiologist(),
              ),
              onTapSpecialist: null,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Find Cardiologists near you'), findsNothing);
      },
    );

    // ── Doctor recommendation cards ─────────────────────────────────

    testWidgets('renders recommended doctor cards', (tester) async {
      final doctors = [
        doctorBasic(placeId: 'd1', name: 'Dr. Smith', rating: 4.5),
        doctorBasic(placeId: 'd2', name: 'Dr. Jones', rating: 4.2),
      ];

      await tester.pumpWidget(
        _buildBubble(
          ChatBubble(
            message: chatMessageAi(
              text: 'Here are some doctors.',
              analysis: analysisCardiologist(),
            ),
            recommendedDoctors: doctors,
            onBookDoctor: (_) {},
            onViewDoctorProfile: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dr. Smith'), findsOneWidget);
      expect(find.text('Dr. Jones'), findsOneWidget);
      expect(find.text('Recommended Cardiologist'), findsOneWidget);
    });

    testWidgets('calls onBookDoctor when book button is tapped', (
      tester,
    ) async {
      DoctorModel? booked;
      final doctor = doctorBasic(placeId: 'book_me', name: 'Dr. Bookable');

      await tester.pumpWidget(
        _buildBubble(
          ChatBubble(
            message: chatMessageAi(
              text: 'Try this doctor.',
              analysis: analysisCardiologist(),
            ),
            recommendedDoctors: [doctor],
            onBookDoctor: (d) => booked = d,
            onViewDoctorProfile: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find and tap the "Book" button within the recommendation card
      await tester.tap(find.text('Book'));
      expect(booked, isNotNull);
      expect(booked!.placeId, 'book_me');
    });

    testWidgets('calls onViewDoctorProfile when profile area is tapped', (
      tester,
    ) async {
      DoctorModel? viewed;
      final doctor = doctorBasic(placeId: 'view_me', name: 'Dr. Viewable');

      await tester.pumpWidget(
        _buildBubble(
          ChatBubble(
            message: chatMessageAi(
              text: 'Check this doctor out.',
              analysis: analysisCardiologist(),
            ),
            recommendedDoctors: [doctor],
            onBookDoctor: (_) {},
            onViewDoctorProfile: (d) => viewed = d,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the doctor's name — it should trigger onViewDoctorProfile
      await tester.tap(find.text('Dr. Viewable'));
      expect(viewed, isNotNull);
      expect(viewed!.placeId, 'view_me');
    });

    // ── Timestamp ───────────────────────────────────────────────────

    testWidgets('shows timestamp for user message', (tester) async {
      final ts = DateTime(2025, 6, 15, 14, 30);
      await tester.pumpWidget(
        _buildBubble(
          ChatBubble(
            message: chatMessageUser(text: 'Hello', timestamp: ts),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 14:30 → "14:30"
      expect(find.text('14:30'), findsOneWidget);
    });

    testWidgets('shows timestamp for AI message', (tester) async {
      final ts = DateTime(2025, 6, 15, 9, 5);
      await tester.pumpWidget(
        _buildBubble(
          ChatBubble(
            message: chatMessageAi(text: 'Hello', timestamp: ts),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('9:05'), findsOneWidget);
    });

    testWidgets('pads minute with leading zero', (tester) async {
      final ts = DateTime(2025, 6, 15, 8, 3);
      await tester.pumpWidget(
        _buildBubble(
          ChatBubble(
            message: chatMessageUser(text: 'Hi', timestamp: ts),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('8:03'), findsOneWidget);
    });

    // ── Animation ───────────────────────────────────────────────────

    testWidgets('renders with showAnimation = false', (tester) async {
      await tester.pumpWidget(
        _buildBubble(
          ChatBubble(
            message: chatMessageUser(text: 'Quick test'),
            showAnimation: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quick test'), findsOneWidget);
    });
  });
}
