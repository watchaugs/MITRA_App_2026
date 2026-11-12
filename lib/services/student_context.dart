import 'telemetry_enums.dart';

/// Immutable snapshot of everything we know about a student + device for
/// the current session. Replaces the ~28 mutable `static` fields from the
/// original TelemetryService.
///
/// Why immutable: the old version let any code anywhere mutate
/// `TelemetryService._connectivityType` etc. as a side effect, which made
/// the static context a shared-mutable-state hazard (especially under
/// concurrent event logging, and across hot-reload/test boundaries where a
/// "second session" would silently inherit the first one's data). An
/// instance of this class is built once via [StudentContext.load] and
/// handed to a [TelemetryService] instance; updating connectivity or
/// consent produces a *new* context via [copyWith] rather than mutating
/// shared state in place.
class StudentContext {
  // Identity & Location
  final String studentId;
  final String? state;
  final String? district;
  final String? schoolId;
  final String? classGrade;
  final Board board;
  final String? subject;

  // Language & Location
  final String? language;
  final AreaType areaType;
  final String? geofenceId;

  // Demographics (DPDPA) — only ever serialized if consent is affirmative.
  final String? gender;
  final AgeGroup ageGroup;
  final SocioeconomicStatus socioeconomicStatus;
  final DisabilityStatus disabilityStatus;
  final MinorityStatus minorityStatus;
  final bool? isFirstGenerationLearner;
  final MobileOwnership mobileOwnership;
  final String? deviceTier; // 'low' | 'medium' | 'high' — from DeviceProbe

  // Consent & Data Governance (DPDPA 2023)
  final ConsentStatus parentalConsentStatus;
  final ConsentStatus dataRetentionConsent;
  final DateTime? consentTimestamp;
  final String? consentVersion;

  // Content & Academic Context
  final NcertMapped ncertMapped;
  final BloomsLevel bloomsLevel;
  final ContentStatus contentStatus;
  final ArTier arTier;
  final RiskLevel riskLevel;

  // Device & Network
  final String? deviceModel;
  final String? osVersion;
  final bool? isArCapable;
  final ConnectivityType connectivityType;

  const StudentContext({
    required this.studentId,
    this.state,
    this.district,
    this.schoolId,
    this.classGrade,
    this.board = Board.unknown,
    this.subject,
    this.language,
    this.areaType = AreaType.unknown,
    this.geofenceId,
    this.gender,
    this.ageGroup = AgeGroup.unknown,
    this.socioeconomicStatus = SocioeconomicStatus.unknown,
    this.disabilityStatus = DisabilityStatus.unknown,
    this.minorityStatus = MinorityStatus.unknown,
    this.isFirstGenerationLearner,
    this.mobileOwnership = MobileOwnership.unknown,
    this.parentalConsentStatus = ConsentStatus.unknown,
    this.dataRetentionConsent = ConsentStatus.unknown,
    this.consentTimestamp,
    this.consentVersion,
    this.ncertMapped = NcertMapped.unknown,
    this.bloomsLevel = BloomsLevel.unknown,
    this.contentStatus = ContentStatus.unknown,
    this.arTier = ArTier.unknown,
    this.riskLevel = RiskLevel.unknown,
    this.deviceModel,
    this.deviceTier,
    this.osVersion,
    this.isArCapable,
    this.connectivityType = ConnectivityType.unknown,
  });

  /// Fail-closed consent check. Both parental consent AND data retention
  /// consent must be explicitly affirmative — anything pending, denied,
  /// expired, or unparsed ("unknown") is treated as NOT consented.
  ///
  /// This is the gate that was missing in the original implementation:
  /// there, consent status was just another field shipped alongside the
  /// data it was supposed to protect, never actually checked before a
  /// write happened.
  bool get hasValidConsent =>
      parentalConsentStatus.isAffirmative && dataRetentionConsent.isAffirmative;

  /// Demographic fields are the DPDPA-sensitive ones. Returns an empty map
  /// (fields omitted, not null-valued — see note in [TelemetryService])
  /// when consent isn't affirmative.
  Map<String, dynamic> get demographicsIfConsented {
    if (!hasValidConsent) return const {};
    return {
      'gender': gender,
      'age_group': ageGroup.wireValue,
      'socioeconomic_status': socioeconomicStatus.wireValue,
      'disability_status': disabilityStatus.wireValue,
      'minority_status': minorityStatus.wireValue,
      'first_generation_learner': isFirstGenerationLearner,
      'mobile_ownership': mobileOwnership.wireValue,
    };
  }

  Map<String, dynamic> toBaseEventJson() => {
        'student_id': studentId,
        'state': state,
        'district': district,
        'school_id': schoolId,
        'subject': subject,
        'class': classGrade,
        'board': board.wireValue,
        'language': language,
        'area_type': areaType.wireValue,
        'geofence_id': geofenceId,
        ...demographicsIfConsented,
        'parental_consent_status': parentalConsentStatus.wireValue,
        'data_retention_consent': dataRetentionConsent.wireValue,
        'consent_timestamp': consentTimestamp?.toIso8601String(),
        'consent_version': consentVersion,
        'ncert_mapped': ncertMapped.wireValue,
        'blooms_level': bloomsLevel.wireValue,
        'content_status': contentStatus.wireValue,
        'ar_tier': arTier.wireValue,
        'risk_level': riskLevel.wireValue,
        'device_model': deviceModel,
        'device_tier': deviceTier,
        'os_version': osVersion,
        'ar_capable': isArCapable,
        'connectivity_type': connectivityType.wireValue,
      };

  /// Build a context from a raw Firestore student document + device probe
  /// results. Centralizes the string->enum parsing the original did inline
  /// (and didn't do at all, for most fields).
  factory StudentContext.fromFirestore({
    required String studentId,
    required Map<String, dynamic> doc,
    String? deviceModel,
    String? deviceTier,
    String? osVersion,
    bool? isArCapable,
  }) {
    DateTime? consentTs;
    final rawConsentTs = doc['consent_timestamp'];
    if (rawConsentTs is String) {
      try {
        consentTs = DateTime.parse(rawConsentTs);
      } catch (_) {
        consentTs = null; // malformed timestamp -> treat as absent, don't throw
      }
    }

    return StudentContext(
      studentId: studentId,
      state: doc['state'] as String?,
      district: doc['district'] as String?,
      schoolId: doc['school_id'] as String?,
      classGrade: doc['class_grade'] as String?,
      board: Board.fromWire(doc['board'] as String?),
      subject: doc['subject'] as String?,
      language: doc['language'] as String?,
      areaType: AreaType.fromWire(doc['area_type'] as String?),
      geofenceId: doc['geofence_id'] as String?,
      gender: doc['gender'] as String?,
      ageGroup: AgeGroup.fromWire(doc['age_group'] as String?),
      socioeconomicStatus:
          SocioeconomicStatus.fromWire(doc['socioeconomic_status'] as String?),
      disabilityStatus:
          DisabilityStatus.fromWire(doc['disability_status'] as String?),
      minorityStatus:
          MinorityStatus.fromWire(doc['minority_status'] as String?),
      isFirstGenerationLearner: doc['first_generation_learner'] as bool?,
      mobileOwnership:
          MobileOwnership.fromWire(doc['mobile_ownership'] as String?),
      parentalConsentStatus:
          ConsentStatus.fromWire(doc['parental_consent_status'] as String?),
      dataRetentionConsent:
          ConsentStatus.fromWire(doc['data_retention_consent'] as String?),
      consentTimestamp: consentTs,
      consentVersion: doc['consent_version'] as String?,
      ncertMapped: NcertMapped.fromWire(doc['ncert_mapped'] as String?),
      bloomsLevel: BloomsLevel.fromWire(doc['blooms_level'] as String?),
      contentStatus: ContentStatus.fromWire(doc['content_status'] as String?),
      arTier: ArTier.fromWire(doc['ar_tier'] as String?),
      riskLevel: RiskLevel.fromWire(doc['risk_level'] as String?),
      deviceModel: deviceModel,
      deviceTier: deviceTier,
      osVersion: osVersion,
      isArCapable: isArCapable,
    );
  }

  StudentContext copyWith({
    ConnectivityType? connectivityType,
    ConsentStatus? parentalConsentStatus,
    ConsentStatus? dataRetentionConsent,
    DateTime? consentTimestamp,
    String? consentVersion,
    String? gender,
    MobileOwnership? mobileOwnership,
  }) {
    return StudentContext(
      studentId: studentId,
      state: state,
      district: district,
      schoolId: schoolId,
      classGrade: classGrade,
      board: board,
      subject: subject,
      language: language,
      areaType: areaType,
      geofenceId: geofenceId,
      gender: gender ?? this.gender,
      ageGroup: ageGroup,
      socioeconomicStatus: socioeconomicStatus,
      disabilityStatus: disabilityStatus,
      minorityStatus: minorityStatus,
      isFirstGenerationLearner: isFirstGenerationLearner,
      mobileOwnership: mobileOwnership ?? this.mobileOwnership,
      parentalConsentStatus:
          parentalConsentStatus ?? this.parentalConsentStatus,
      dataRetentionConsent: dataRetentionConsent ?? this.dataRetentionConsent,
      consentTimestamp: consentTimestamp ?? this.consentTimestamp,
      consentVersion: consentVersion ?? this.consentVersion,
      ncertMapped: ncertMapped,
      bloomsLevel: bloomsLevel,
      contentStatus: contentStatus,
      arTier: arTier,
      riskLevel: riskLevel,
      deviceModel: deviceModel,
      osVersion: osVersion,
      isArCapable: isArCapable,
      connectivityType: connectivityType ?? this.connectivityType,
    );
  }
}
