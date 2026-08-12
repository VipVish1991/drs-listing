import '../utils/text_sanitizer.dart';
import 'unavailable_range.dart';

/// Represents a doctor/clinic result from the Google Places API.
///
/// Covers both the Text Search (list) and Place Details (full) responses
/// so that every field the API returns is available to the UI without
/// additional lookups.
class DoctorModel {
  // ── Core identifiers ──────────────────────────────────────────────
  final String placeId;
  final String name;
  final String? userId;

  // ── Contact & location ────────────────────────────────────────────
  final String? address; // formatted_address
  final String? vicinity; // shorter address (from text search)
  final double? latitude;
  final double? longitude;
  final String? phoneNumber; // formatted_phone_number
  final String? internationalPhoneNumber;
  final String? website;
  final String? url; // Maps URL (place detail)
  final String? plusCode; // global_code e.g. "7MH37M6G+R6"

  // ── Ratings & reviews ─────────────────────────────────────────────
  final double? rating;
  final int? userRatingsTotal;
  final bool? isOpen; // open_now convenience
  final String? businessStatus; // "OPERATIONAL", "CLOSED_TEMPORARILY", …
  final int? priceLevel; // 0=free … 4=very expensive

  // ── Photos ─────────────────────────────────────────────────────────
  /// Photo-reference strings from Google Places Photo API.
  final List<String> photos;

  /// Full photo metadata returned by Place Details (photo_reference → map).
  final List<Map<String, dynamic>> photoDetails;

  // ── Opening hours ──────────────────────────────────────────────────
  /// Human-readable weekday lines:  "Monday: 9:30 AM – 1:00 PM, …"
  final List<String> openingHours;

  /// Raw opening hours period maps from the Details API.
  final List<Map<String, dynamic>> openingHoursPeriods;

  // ── Reviews ────────────────────────────────────────────────────────
  /// Full review objects from the Details API.
  final List<Map<String, dynamic>> reviews;

  // ── Classification ─────────────────────────────────────────────────
  final String? specialization;
  final String? hospitalName;
  final List<String> types; // e.g. ["doctor", "health", "hospital"]
  // (featureType/maki removed — now using Google Places types)

  // ── Address components ─────────────────────────────────────────────
  /// e.g. [{"long_name": "492001", "short_name": "492001", "types": ["postal_code"]}, …]
  final List<Map<String, dynamic>> addressComponents;

  // ── Editorial summary ──────────────────────────────────────────────
  final String? editorialSummary;

  // ── Google Places API additions ─────────────────────────────────────
  /// Google's primary place type, more specific than types[] array.
  /// e.g. "cardiologist", "general_doctor", "dentist", "hospital"
  final String? primaryType;

  /// Whether the entrance is wheelchair-accessible.
  final bool? wheelchairAccessible;

  /// Real-time opening hours that account for holidays/temporary changes.
  /// JSON object with keys like `weekday_text`, `periods`, `open_now`.
  final Map<String, dynamic>? currentOpeningHours;

  // ── UI helpers ──────────────────────────────────────────────────────
  final String? distance; // human-friendly string injected by the controller
  final Map<String, String>?
  symptomsMap; // symptom → emoji when navigating from AI
  final int?
  experienceYears; // not from API – filled by user input if available

  // ── Doctor-set availability ─────────────────────────────────────────
  /// Inclusive date ranges when the doctor is unavailable (leave/holiday),
  /// set from the doctor profile's Available/Unavailable flow and stored in
  /// the doctors table's `unavailable_ranges` JSONB column.
  final List<UnavailableRange> unavailableRanges;

  // ── Doctor-set payments ─────────────────────────────────────────────
  /// The clinic's UPI VPA that receives online consultation fees (e.g.
  /// `clinic@okhdfcbank`), set from the doctor profile's UPI ID card and
  /// stored in the doctors table's `upi_id` column. When null the app-wide
  /// default [AppConstants.upiReceiverVpa] is used in the booking flow.
  final String? upiId;

  // ══════════════════════════════════════════════════════════════════
  // Constructor
  // ══════════════════════════════════════════════════════════════════
  DoctorModel({
    required this.placeId,
    required this.name,
    this.userId,
    this.address,
    this.vicinity,
    this.latitude,
    this.longitude,
    this.phoneNumber,
    this.internationalPhoneNumber,
    this.website,
    this.url,
    this.plusCode,
    this.rating,
    this.userRatingsTotal,
    this.isOpen,
    this.businessStatus,
    this.priceLevel,
    this.photos = const [],
    this.photoDetails = const [],
    this.openingHours = const [],
    this.openingHoursPeriods = const [],
    this.reviews = const [],
    this.specialization,
    this.hospitalName,
    this.types = const [],
    this.addressComponents = const [],
    this.editorialSummary,

    this.primaryType,
    this.wheelchairAccessible,
    this.currentOpeningHours,

    this.distance,
    this.symptomsMap,
    this.experienceYears,
    this.unavailableRanges = const [],
    this.upiId,
  });

  // ══════════════════════════════════════════════════════════════════
  // Factory: from Google Places API JSON (legacy — kept for Supabase data)
  // ══════════════════════════════════════════════════════════════════
  factory DoctorModel.fromGooglePlaces(Map<String, dynamic> json) {
    // ---- geometry ----
    double? lat;
    double? lng;
    if (json['geometry'] != null) {
      final location = json['geometry']['location'];
      if (location != null) {
        lat = (location['lat'] as num?)?.toDouble();
        lng = (location['lng'] as num?)?.toDouble();
      }
    }

    // ---- photos ----
    final List<Map<String, dynamic>> photoDetailsList = [];
    final List<String> photoRefs = [];
    if (json['photos'] != null) {
      for (final p in (json['photos'] as List)) {
        final ref = p['photo_reference']?.toString() ?? '';
        if (ref.isNotEmpty) {
          photoRefs.add(ref);
          photoDetailsList.add({
            'photo_reference': ref,
            'height': p['height'],
            'width': p['width'],
            'html_attributions': p['html_attributions'],
          });
        }
      }
    }

    // ---- opening hours ----
    final hoursData = json['opening_hours'];
    List<String> weekdayText = [];
    List<Map<String, dynamic>> periods = [];
    if (hoursData != null) {
      if (hoursData['weekday_text'] != null) {
        weekdayText = List<String>.from(
          hoursData['weekday_text'],
        ).map(TextSanitizer.sanitize).toList();
      }
      if (hoursData['periods'] != null) {
        periods = List<Map<String, dynamic>>.from(hoursData['periods']);
      }
    }

    // ---- reviews (sanitize free-text so bad UTF-16 can't crash layout) ----
    List<Map<String, dynamic>> reviews = [];
    if (json['reviews'] != null) {
      reviews = List<Map<String, dynamic>>.from(json['reviews'])
          .map((r) => Map<String, dynamic>.from(r))
          .map((r) {
            if (r['text'] != null) {
              r['text'] = TextSanitizer.sanitize(r['text'].toString());
            }
            if (r['author_name'] != null) {
              r['author_name'] = TextSanitizer.sanitize(
                r['author_name'].toString(),
              );
            }
            return r;
          })
          .toList();
    }

    // ---- types ----
    final List<String> types =
        (json['types'] as List?)?.map((e) => e.toString()).toList() ?? [];

    // ---- address components ----
    List<Map<String, dynamic>> addrComponents = [];
    if (json['address_components'] != null) {
      addrComponents = List<Map<String, dynamic>>.from(
        json['address_components'],
      );
    }

    // ---- plus_code ----
    String? plusCode;
    if (json['plus_code'] != null) {
      plusCode = json['plus_code']['global_code']?.toString();
    }

    // ---- phone ----
    final phone =
        json['formatted_phone_number']?.toString() ??
        json['international_phone_number']?.toString();

    // ---- name → hospitalName / specialization ----
    final name = TextSanitizer.sanitize(json['name']?.toString() ?? '');
    final vicinity = TextSanitizer.sanitize(json['vicinity']?.toString());
    final isDoctor = types.contains('doctor');

    // ---- primary_type ----
    final primaryType = TextSanitizer.sanitize(
      json['primary_type']?.toString(),
    );

    // ---- wheelchair_accessible_entrance ----
    final wheelchairAccessible =
        json['wheelchair_accessible_entrance'] as bool?;

    // ---- current_opening_hours ----
    Map<String, dynamic>? currentHours;
    if (json['current_opening_hours'] != null) {
      currentHours = Map<String, dynamic>.from(json['current_opening_hours']);
    }

    return DoctorModel(
      placeId: json['place_id']?.toString() ?? '',
      name: name,
      vicinity: vicinity,
      address: TextSanitizer.sanitize(
        json['formatted_address']?.toString() ?? vicinity,
      ),
      latitude: lat,
      longitude: lng,
      phoneNumber: TextSanitizer.sanitize(phone),
      internationalPhoneNumber: TextSanitizer.sanitize(
        json['international_phone_number']?.toString(),
      ),
      website: TextSanitizer.sanitize(json['website']?.toString()),
      url: TextSanitizer.sanitize(json['url']?.toString()),
      plusCode: TextSanitizer.sanitize(plusCode),
      rating: (json['rating'] as num?)?.toDouble(),
      userRatingsTotal: json['user_ratings_total'] as int?,
      isOpen: hoursData?['open_now'] as bool?,
      businessStatus: TextSanitizer.sanitize(
        json['business_status']?.toString(),
      ),
      priceLevel: json['price_level'] as int?,
      photos: photoRefs,
      photoDetails: photoDetailsList,
      openingHours: weekdayText,
      openingHoursPeriods: periods,
      reviews: reviews,
      specialization: isDoctor ? name : null,
      hospitalName: isDoctor ? null : name,
      types: types,
      addressComponents: addrComponents,
      editorialSummary: TextSanitizer.sanitize(
        (json['editorial_summary'] as Map<String, dynamic>?)?['overview']
            ?.toString(),
      ),

      primaryType: primaryType,
      wheelchairAccessible: wheelchairAccessible,
      currentOpeningHours: currentHours,
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // Factory: from Google Places NEW API JSON (legacy — kept for Supabase data)
  // ══════════════════════════════════════════════════════════════════
  factory DoctorModel.fromNewPlacesApi(Map<String, dynamic> json) {
    // ---- location ----
    double? lat;
    double? lng;
    if (json['location'] != null) {
      lat = (json['location']['latitude'] as num?)?.toDouble();
      lng = (json['location']['longitude'] as num?)?.toDouble();
    }

    // ---- displayName ----
    final displayName = json['displayName'] as Map<String, dynamic>?;
    final name = TextSanitizer.sanitize(displayName?['text']?.toString() ?? '');

    // ---- photos ----
    final List<String> photoRefs = [];
    final List<Map<String, dynamic>> photoDetailsList = [];
    if (json['photos'] != null) {
      for (final p in (json['photos'] as List)) {
        final name = p['name']?.toString() ?? '';
        if (name.isNotEmpty) {
          photoRefs.add(name);
          photoDetailsList.add({'name': name});
        }
      }
    }

    // ---- opening hours ----
    final hoursData = json['openingHours'] as Map<String, dynamic>?;
    List<String> weekdayText = [];
    if (hoursData != null && hoursData['weekdayDescriptions'] != null) {
      weekdayText = List<String>.from(
        hoursData['weekdayDescriptions'],
      ).map(TextSanitizer.sanitize).toList();
    }

    // ---- reviews (sanitize free-text so bad UTF-16 can't crash layout) ----
    List<Map<String, dynamic>> reviews = [];
    if (json['reviews'] != null) {
      reviews = List<Map<String, dynamic>>.from(json['reviews'])
          .map((r) => Map<String, dynamic>.from(r))
          .map((r) {
            if (r['text'] != null) {
              r['text'] = TextSanitizer.sanitize(r['text'].toString());
            }
            if (r['author_name'] != null) {
              r['author_name'] = TextSanitizer.sanitize(
                r['author_name'].toString(),
              );
            }
            return r;
          })
          .toList();
    }

    // ---- types ----
    final List<String> types =
        (json['types'] as List?)?.map((e) => e.toString()).toList() ?? [];

    // ---- address components ----
    List<Map<String, dynamic>> addrComponents = [];
    if (json['addressComponents'] != null) {
      addrComponents = List<Map<String, dynamic>>.from(
        json['addressComponents'],
      );
    }

    // ---- phone ----
    final phone =
        json['formattedPhoneNumber']?.toString() ??
        json['internationalPhoneNumber']?.toString();

    // ---- name → hospitalName / specialization ----
    final vicinity = TextSanitizer.sanitize(
      json['formattedAddress']?.toString(),
    );
    final isDoctor = types.contains('doctor');

    // ---- primary_type (new API: primaryType) ----
    final primaryType = TextSanitizer.sanitize(json['primaryType']?.toString());

    // ---- wheelchair_accessible (new API) ----
    final wheelchairAccessible = json['wheelchairAccessibleEntrance'] as bool?;

    // ---- current_opening_hours (new API: currentOpeningHours) ----
    Map<String, dynamic>? currentHours;
    if (json['currentOpeningHours'] != null) {
      currentHours = Map<String, dynamic>.from(json['currentOpeningHours']);
    }

    return DoctorModel(
      placeId: json['id']?.toString() ?? '',
      name: name,
      vicinity: vicinity,
      address: TextSanitizer.sanitize(json['formattedAddress']?.toString()),
      latitude: lat,
      longitude: lng,
      phoneNumber: TextSanitizer.sanitize(phone),
      internationalPhoneNumber: TextSanitizer.sanitize(
        json['internationalPhoneNumber']?.toString(),
      ),
      website: TextSanitizer.sanitize(json['website']?.toString()),
      url: TextSanitizer.sanitize(json['googleMapsUri']?.toString()),
      rating: (json['rating'] as num?)?.toDouble(),
      userRatingsTotal: json['userRatingCount'] as int?,
      isOpen: null, // Not available in new API list response
      businessStatus: TextSanitizer.sanitize(
        json['businessStatus']?.toString(),
      ),
      priceLevel: json['priceLevel'] as int?,
      photos: photoRefs,
      photoDetails: photoDetailsList,
      openingHours: weekdayText,
      openingHoursPeriods: [],
      reviews: reviews,
      specialization: isDoctor ? name : null,
      hospitalName: isDoctor ? null : name,
      types: types,
      addressComponents: addrComponents,
      editorialSummary: TextSanitizer.sanitize(
        (json['editorialSummary'] as Map<String, dynamic>?)?['overview']
            ?.toString(),
      ),

      primaryType: primaryType,
      wheelchairAccessible: wheelchairAccessible,
      currentOpeningHours: currentHours,
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // Factory: from app-local JSON (e.g. Supabase)
  // ══════════════════════════════════════════════════════════════════
  factory DoctorModel.fromJson(Map<String, dynamic> json) {
    return DoctorModel(
      placeId: json['place_id']?.toString() ?? '',
      name: TextSanitizer.sanitize(json['name']?.toString() ?? ''),
      userId: json['user_id']?.toString(),
      address: _sanitizeNullable(json['address']?.toString()),
      vicinity: _sanitizeNullable(json['vicinity']?.toString()),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      phoneNumber: _sanitizeNullable(json['phone_number']?.toString()),
      internationalPhoneNumber: _sanitizeNullable(
        json['international_phone_number']?.toString(),
      ),
      website: _sanitizeNullable(json['website']?.toString()),
      url: _sanitizeNullable(json['url']?.toString()),
      plusCode: _sanitizeNullable(json['plus_code']?.toString()),
      rating: (json['rating'] as num?)?.toDouble(),
      userRatingsTotal: json['user_ratings_total'] as int?,
      isOpen: json['is_open'] as bool?,
      businessStatus: _sanitizeNullable(json['business_status']?.toString()),
      priceLevel: json['price_level'] as int?,
      photos: List<String>.from(json['photos'] ?? []),
      photoDetails: List<Map<String, dynamic>>.from(
        json['photo_details'] ?? [],
      ),
      openingHours: List<String>.from(
        json['opening_hours'] ?? [],
      ).map(TextSanitizer.sanitize).toList(),
      openingHoursPeriods: List<Map<String, dynamic>>.from(
        json['opening_hours_periods'] ?? [],
      ),
      reviews: (json['reviews'] as List? ?? [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .map((r) {
            if (r['text'] != null) {
              r['text'] = TextSanitizer.sanitize(r['text'].toString());
            }
            if (r['author_name'] != null) {
              r['author_name'] = TextSanitizer.sanitize(
                r['author_name'].toString(),
              );
            }
            return r;
          })
          .toList(),
      specialization: _sanitizeNullable(json['specialization']?.toString()),
      hospitalName: _sanitizeNullable(json['hospital_name']?.toString()),
      types: List<String>.from(json['types'] ?? []),
      addressComponents: List<Map<String, dynamic>>.from(
        json['address_components'] ?? [],
      ),
      editorialSummary: _sanitizeNullable(
        json['editorial_summary']?.toString(),
      ),

      primaryType: _sanitizeNullable(json['primary_type']?.toString()),
      wheelchairAccessible: json['wheelchair_accessible'] as bool?,
      currentOpeningHours: json['current_opening_hours'] != null
          ? Map<String, dynamic>.from(json['current_opening_hours'])
          : null,

      distance: _sanitizeNullable(json['distance']?.toString()),
      experienceYears: json['experience_years'] as int?,
      unavailableRanges: UnavailableRange.listFromJson(
        json['unavailable_ranges'],
      ),
      upiId: _sanitizeNullable(json['upi_id']?.toString()),
    );
  }

  /// Sanitize an optional string field while preserving `null` for absent
  /// values.
  ///
  /// [TextSanitizer.sanitize] collapses `null` to `''`, which makes
  /// "missing" and "empty" indistinguishable. Optional fields (e.g.
  /// `phone_number`) must stay `null` when the key is absent — the model
  /// contract, UI null-checks, and `SupabaseService.saveDoctorToDb`'s
  /// null-dropping upsert all depend on it (an empty string would be
  /// written over real DB values).
  static String? _sanitizeNullable(String? value) =>
      value == null ? null : TextSanitizer.sanitize(value);

  // ══════════════════════════════════════════════════════════════════
  // copyWith
  // ══════════════════════════════════════════════════════════════════
  DoctorModel copyWith({
    String? placeId,
    String? name,
    String? userId,
    String? address,
    String? vicinity,
    double? latitude,
    double? longitude,
    String? phoneNumber,
    String? internationalPhoneNumber,
    String? website,
    String? url,
    String? plusCode,
    double? rating,
    int? userRatingsTotal,
    bool? isOpen,
    String? businessStatus,
    int? priceLevel,
    List<String>? photos,
    List<Map<String, dynamic>>? photoDetails,
    List<String>? openingHours,
    List<Map<String, dynamic>>? openingHoursPeriods,
    List<Map<String, dynamic>>? reviews,
    String? specialization,
    String? hospitalName,
    List<String>? types,
    List<Map<String, dynamic>>? addressComponents,
    String? editorialSummary,

    String? primaryType,
    bool? wheelchairAccessible,
    Map<String, dynamic>? currentOpeningHours,

    String? distance,
    Map<String, String>? symptomsMap,
    int? experienceYears,
    List<UnavailableRange>? unavailableRanges,
    String? upiId,
  }) {
    return DoctorModel(
      placeId: placeId ?? this.placeId,
      name: name ?? this.name,
      userId: userId ?? this.userId,
      address: address ?? this.address,
      vicinity: vicinity ?? this.vicinity,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      internationalPhoneNumber:
          internationalPhoneNumber ?? this.internationalPhoneNumber,
      website: website ?? this.website,
      url: url ?? this.url,
      plusCode: plusCode ?? this.plusCode,
      rating: rating ?? this.rating,
      userRatingsTotal: userRatingsTotal ?? this.userRatingsTotal,
      isOpen: isOpen ?? this.isOpen,
      businessStatus: businessStatus ?? this.businessStatus,
      priceLevel: priceLevel ?? this.priceLevel,
      photos: photos ?? this.photos,
      photoDetails: photoDetails ?? this.photoDetails,
      openingHours: openingHours ?? this.openingHours,
      openingHoursPeriods: openingHoursPeriods ?? this.openingHoursPeriods,
      reviews: reviews ?? this.reviews,
      specialization: specialization ?? this.specialization,
      hospitalName: hospitalName ?? this.hospitalName,
      types: types ?? this.types,
      addressComponents: addressComponents ?? this.addressComponents,
      editorialSummary: editorialSummary ?? this.editorialSummary,

      primaryType: primaryType ?? this.primaryType,
      wheelchairAccessible: wheelchairAccessible ?? this.wheelchairAccessible,
      currentOpeningHours: currentOpeningHours ?? this.currentOpeningHours,

      distance: distance ?? this.distance,
      symptomsMap: symptomsMap ?? this.symptomsMap,
      experienceYears: experienceYears ?? this.experienceYears,
      unavailableRanges: unavailableRanges ?? this.unavailableRanges,
      upiId: upiId ?? this.upiId,
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // toJson
  // ══════════════════════════════════════════════════════════════════
  Map<String, dynamic> toJson() {
    return {
      'place_id': placeId,
      'name': name,
      'user_id': userId,
      'address': address,
      'vicinity': vicinity,
      'latitude': latitude,
      'longitude': longitude,
      'phone_number': phoneNumber,
      'international_phone_number': internationalPhoneNumber,
      'website': website,
      'url': url,
      'plus_code': plusCode,
      'rating': rating,
      'user_ratings_total': userRatingsTotal,
      'is_open': isOpen,
      'business_status': businessStatus,
      'price_level': priceLevel,
      'photos': photos,
      'photo_details': photoDetails,
      'opening_hours': openingHours,
      'opening_hours_periods': openingHoursPeriods,
      'reviews': reviews,
      'specialization': specialization,
      'hospital_name': hospitalName,
      'types': types,
      'address_components': addressComponents,
      'editorial_summary': editorialSummary,

      'primary_type': primaryType,
      'wheelchair_accessible': wheelchairAccessible,
      'current_opening_hours': currentOpeningHours,

      'distance': distance,
      'experience_years': experienceYears,
      'unavailable_ranges': unavailableRanges.map((r) => r.toJson()).toList(),
      'upi_id': upiId,
    };
  }
}
