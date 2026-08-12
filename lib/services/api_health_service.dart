import 'package:http/http.dart' as http;
import '../config/constants.dart';

/// Result of a single API health check.
class ApiCheckResult {
  final String serviceName;
  final bool healthy;
  final String? message;

  const ApiCheckResult({
    required this.serviceName,
    required this.healthy,
    this.message,
  });
}

/// Aggregated health status for all checked APIs.
class ApiHealthResult {
  final List<ApiCheckResult> checks;
  final bool allHealthy;
  final bool hasMissingKeys;

  const ApiHealthResult({
    required this.checks,
    required this.allHealthy,
    required this.hasMissingKeys,
  });
}

/// Performs lightweight health checks on the app's external API dependencies.
///
/// This runs at startup to proactively warn users when API keys are missing
/// or invalid, so they don't face cryptic errors later.
class ApiHealthService {
  static final ApiHealthService _instance = ApiHealthService._internal();
  factory ApiHealthService() => _instance;
  ApiHealthService._internal();

  ApiHealthResult? _cachedResult;

  /// The most recent health result (null until [checkAll] completes).
  ApiHealthResult? get lastResult => _cachedResult;

  /// Run all API health checks. Non-blocking — returns immediately if
  /// a result was already computed.
  Future<ApiHealthResult> checkAll() async {
    if (_cachedResult != null) return _cachedResult!;

    final checks = <ApiCheckResult>[];

    // 1. Check that .env keys are present
    final googleKeyPresent = AppConstants.googleMapsApiKey.isNotEmpty;
    final groqKeyPresent = AppConstants.groqApiKey.isNotEmpty;

    if (!googleKeyPresent) {
      checks.add(const ApiCheckResult(
        serviceName: 'Google Places',
        healthy: false,
        message: 'API key is missing. Add GOOGLE_MAPS_API_KEY to your .env file.',
      ));
    }

    if (!groqKeyPresent) {
      checks.add(const ApiCheckResult(
        serviceName: 'Groq AI',
        healthy: false,
        message: 'API key is missing. Add GROQ_API_KEY to your .env file.',
      ));
    }

    // 2. Verify keys by making lightweight HTTP calls (in parallel)
    final futures = <Future<ApiCheckResult>>[];

    if (googleKeyPresent) {
      futures.add(_checkGooglePlaces());
    }
    if (groqKeyPresent) {
      futures.add(_checkGroq());
    }

    if (futures.isNotEmpty) {
      final results = await Future.wait(futures);
      checks.addAll(results);
    }

    final allHealthy = checks.every((c) => c.healthy);
    final hasMissingKeys = !googleKeyPresent || !groqKeyPresent;

    _cachedResult = ApiHealthResult(
      checks: checks,
      allHealthy: allHealthy,
      hasMissingKeys: hasMissingKeys,
    );

    return _cachedResult!;
  }

  /// Verify the Google Places API key with a lightweight text search.
  Future<ApiCheckResult> _checkGooglePlaces() async {
    try {
      final uri = Uri.parse(
        '${AppConstants.googlePlacesBaseUrl}/textsearch/json',
      ).replace(queryParameters: {
        'query': 'hospital',
        'key': AppConstants.googleMapsApiKey,
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return const ApiCheckResult(
          serviceName: 'Google Places',
          healthy: true,
          message: 'API key is valid and the Places API is enabled.',
        );
      }

      return ApiCheckResult(
        serviceName: 'Google Places',
        healthy: false,
        message: 'HTTP ${response.statusCode} — check your API key.',
      );
    } catch (e) {
      return ApiCheckResult(
        serviceName: 'Google Places',
        healthy: false,
        message: 'Network error — ${e.toString()}',
      );
    }
  }

  /// Verify the Groq API key with a lightweight models list request.
  Future<ApiCheckResult> _checkGroq() async {
    try {
      final uri = Uri.parse('${AppConstants.groqBaseUrl}/models');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${AppConstants.groqApiKey}',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return const ApiCheckResult(
          serviceName: 'Groq AI',
          healthy: true,
          message: 'API key is valid.',
        );
      }

      if (response.statusCode == 401) {
        return const ApiCheckResult(
          serviceName: 'Groq AI',
          healthy: false,
          message: 'API key is invalid (401 Unauthorized).',
        );
      }

      return ApiCheckResult(
        serviceName: 'Groq AI',
        healthy: false,
        message: 'HTTP ${response.statusCode} — check your API key.',
      );
    } catch (e) {
      return ApiCheckResult(
        serviceName: 'Groq AI',
        healthy: false,
        message: 'Network error — ${e.toString()}',
      );
    }
  }
}
