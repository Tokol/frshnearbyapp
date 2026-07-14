import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BackendUser {
  const BackendUser({
    required this.onboardingStep,
    required this.verificationStatus,
  });
  final String onboardingStep;
  final String verificationStatus;

  factory BackendUser.fromJson(Map<String, dynamic> json) => BackendUser(
    onboardingStep: json['onboardingStep'] as String,
    verificationStatus: json['verificationStatus'] as String,
  );
}

class ConfirmedLocation {
  const ConfirmedLocation({
    required this.addressLine,
    required this.city,
    required this.postalCode,
    required this.country,
    required this.latitude,
    required this.longitude,
  });
  final String addressLine;
  final String city;
  final String postalCode;
  final String country;
  final double latitude;
  final double longitude;

  Map<String, dynamic> toJson() => {
    'addressLine': addressLine,
    'city': city,
    'postalCode': postalCode,
    'country': country,
    'latitude': latitude,
    'longitude': longitude,
  };
}

class BackendService {
  BackendService({FirebaseAuth? auth})
    : _providedAuth = auth,
      _dio = Dio(
        BaseOptions(
          baseUrl: const String.fromEnvironment(
            'FRSH_API_URL',
            defaultValue: 'https://frshnearby-api.onrender.com/graphql',
          ),
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

  final FirebaseAuth? _providedAuth;
  final Dio _dio;

  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;

  Future<Map<String, dynamic>> _gql(
    String query, [
    Map<String, dynamic> variables = const {},
  ]) async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null) throw StateError('Please sign in again.');
    final response = await _dio.post<Map<String, dynamic>>(
      '',
      data: {'query': query, 'variables': variables},
      options: Options(headers: {'authorization': 'Bearer $token'}),
    );
    final body = response.data ?? const {};
    final errors = body['errors'] as List<dynamic>?;
    if (errors != null && errors.isNotEmpty) {
      throw StateError(
        (errors.first as Map<String, dynamic>)['message'] as String? ??
            'Server request failed.',
      );
    }
    return body['data'] as Map<String, dynamic>;
  }

  Future<BackendUser> session() async {
    final data = await _gql(
      'query { session { user { onboardingStep verificationStatus } } }',
    );
    return BackendUser.fromJson(
      (data['session'] as Map<String, dynamic>)['user'] as Map<String, dynamic>,
    );
  }

  Future<void> confirmLocation(ConfirmedLocation location) => _gql(
    'mutation(\$input: ConfirmLocationInput!) { confirmLocation(input: \$input) { id } }',
    {'input': location.toJson()},
  );

  Future<void> finish({
    required String displayName,
    required String phone,
    required String dateOfBirth,
    String? photoUrl,
    required String accountType,
    ConfirmedLocation? location,
    Map<String, dynamic>? sellerProfile,
  }) async {
    await _gql(
      'mutation(\$input: PersonalProfileInput!) { updatePersonalProfile(input: \$input) { id } }',
      {
        'input': {
          'displayName': displayName,
          'phone': phone,
          'dateOfBirth': dateOfBirth,
          if (photoUrl != null) 'photoUrl': photoUrl,
        },
      },
    );
    await _gql(
      'mutation(\$input: SelectAccountTypeInput!) { selectAccountType(input: \$input) { id } }',
      {
        'input': {'accountType': accountType},
      },
    );
    if (location != null) {
      await confirmLocation(location);
    }
    if (accountType == 'SIDE_HUSTLER') {
      await _gql(
        'mutation(\$input: ProducerProfileInput!) { saveProducerProfile(input: \$input) { id } }',
        {'input': sellerProfile},
      );
      await _gql('mutation { submitForVerification { id } }');
    } else if (accountType == 'BUSINESS') {
      await _gql(
        'mutation(\$input: BusinessProfileInput!) { saveBusinessProfile(input: \$input) { id } }',
        {'input': sellerProfile},
      );
      await _gql('mutation { submitForVerification { id } }');
    }
  }
}
