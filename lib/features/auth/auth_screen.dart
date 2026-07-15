import 'dart:async';

import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import 'auth_service.dart';
import 'backend_service.dart';
import 'location_sheet.dart';
import 'onboarding_progress_store.dart';
import 'onboarding_draft_store.dart';

const _green = Color(0xFF2F6B45);
const _deepGreen = Color(0xFF184D31);
const _ink = Color(0xFF183326);
const _muted = Color(0xFF647267);
const _line = Color(0xFFE2E8DD);
const _mist = Color(0xFFEFF4E9);
const _gold = Color(0xFFE9CD7A);

enum _AccountType { consumer, producer, business }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _controller = PageController();
  final _emailKey = GlobalKey<FormState>();
  final _detailsKey = GlobalKey<FormState>();
  final _businessKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _introController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _farmNameController = TextEditingController();
  final _businessIdController = TextEditingController();
  final _vatController = TextEditingController();
  final _businessAddressController = TextEditingController();
  final _businessCityController = TextEditingController();
  final _businessPostalController = TextEditingController();
  final _authService = AuthService();
  final _backend = BackendService();
  final _progressStore = OnboardingProgressStore();
  final _draftStore = OnboardingDraftStore();
  late final AnimationController _skyController;
  int _page = 0;
  bool _isConsumer = true;
  _AccountType? _sellerType;
  bool _registering = true;
  bool _hidePassword = true;
  bool _authBusy = false;
  String? _socialPhotoUrl;
  Uint8List? _pickedPhotoBytes;
  ConfirmedLocation? _confirmedLocation;
  String? _businessType;
  Timer? _draftTimer;

  _AccountType get _effectiveType => _sellerType ?? _AccountType.consumer;
  int get _reviewPage => _sellerType == _AccountType.business ? 4 : 3;

  @override
  void initState() {
    super.initState();
    _skyController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);
    for (final controller in _draftControllers) {
      controller.addListener(_scheduleDraftSave);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession());
  }

  List<TextEditingController> get _draftControllers => [
    _fullNameController,
    _dateOfBirthController,
    _displayNameController,
    _phoneController,
    _introController,
    _businessNameController,
    _farmNameController,
    _businessIdController,
    _vatController,
    _businessAddressController,
    _businessCityController,
    _businessPostalController,
  ];

  void _scheduleDraftSave() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 450), _saveLocalDraft);
  }

  Future<void> _saveLocalDraft() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    final location = _confirmedLocation;
    await _draftStore.save(uid, {
      'fullName': _fullNameController.text,
      'dateOfBirth': _dateOfBirthController.text,
      'displayName': _displayNameController.text,
      'phone': _phoneController.text,
      'intro': _introController.text,
      'businessName': _businessNameController.text,
      'farmName': _farmNameController.text,
      'businessId': _businessIdController.text,
      'vatNumber': _vatController.text,
      'businessAddress': _businessAddressController.text,
      'businessCity': _businessCityController.text,
      'businessPostalCode': _businessPostalController.text,
      'businessType': _businessType,
      'consumer': _isConsumer,
      'sellerType': _sellerType?.name,
      if (location != null) 'location': location.toJson(),
    });
  }

  Future<void> _restoreLocalDraft(String uid) async {
    final draft = await _draftStore.load(uid);
    if (draft == null || !mounted) return;
    void restore(TextEditingController controller, String key) {
      final value = draft[key] as String?;
      if (controller.text.isEmpty && value?.isNotEmpty == true) {
        controller.text = value!;
      }
    }

    restore(_fullNameController, 'fullName');
    restore(_dateOfBirthController, 'dateOfBirth');
    restore(_displayNameController, 'displayName');
    restore(_phoneController, 'phone');
    restore(_introController, 'intro');
    restore(_businessNameController, 'businessName');
    restore(_farmNameController, 'farmName');
    restore(_businessIdController, 'businessId');
    restore(_vatController, 'vatNumber');
    restore(_businessAddressController, 'businessAddress');
    restore(_businessCityController, 'businessCity');
    restore(_businessPostalController, 'businessPostalCode');
    final seller = draft['sellerType'] as String?;
    final location = draft['location'] as Map<String, dynamic>?;
    setState(() {
      _isConsumer = draft['consumer'] as bool? ?? _isConsumer;
      _sellerType = switch (seller) {
        'producer' => _AccountType.producer,
        'business' => _AccountType.business,
        _ => _sellerType,
      };
      _businessType = draft['businessType'] as String? ?? _businessType;
      if (location != null) {
        _confirmedLocation = ConfirmedLocation(
          addressLine: location['addressLine'] as String? ?? '',
          addressUnit: location['addressUnit'] as String?,
          city: location['city'] as String? ?? '',
          postalCode: location['postalCode'] as String? ?? '',
          country: location['country'] as String? ?? '',
          latitude: (location['latitude'] as num?)?.toDouble() ?? 0,
          longitude: (location['longitude'] as num?)?.toDouble() ?? 0,
        );
      }
    });
  }

  Future<void> _restoreSession() async {
    User? user;
    try {
      user = _authService.currentUser;
    } on FirebaseException {
      // Widget previews/tests may render before Firebase is bootstrapped.
      return;
    }
    if (user == null || !mounted) return;
    _prefillFromUser(user);
    await _restoreLocalDraft(user.uid);
    final usesPassword = user.providerData.any(
      (provider) => provider.providerId == 'password',
    );
    if (usesPassword && !user.emailVerified) {
      _goTo(7);
      return;
    }
    try {
      final profile = await _backend.session();
      if (!mounted) return;
      _restoreBackendProfile(profile);
      _goTo(_resumePage(profile));
    } catch (error) {
      if (mounted) _showAuthError(_serverMessage(error));
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _skyController.dispose();
    _controller.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    _dateOfBirthController.dispose();
    _displayNameController.dispose();
    _phoneController.dispose();
    _introController.dispose();
    _businessNameController.dispose();
    _farmNameController.dispose();
    _businessIdController.dispose();
    _vatController.dispose();
    _businessAddressController.dispose();
    _businessCityController.dispose();
    _businessPostalController.dispose();
    super.dispose();
  }

  Future<void> _runAuthentication(
    Future<UserCredential> Function() action,
  ) async {
    if (_authBusy) return;
    setState(() => _authBusy = true);
    try {
      final credential = await action();
      if (!mounted) return;
      _prefillFromUser(credential.user);
      if (credential.user != null) {
        await _restoreLocalDraft(credential.user!.uid);
      }
      final usesPassword =
          credential.user?.providerData.any(
            (provider) => provider.providerId == 'password',
          ) ??
          false;
      if (usesPassword && !(credential.user?.emailVerified ?? false)) {
        _goTo(7);
        return;
      }
      final profile = await _backend.session();
      if (!mounted) return;
      _restoreBackendProfile(profile);
      _goTo(_resumePage(profile));
    } on AuthCancelledException {
      // Closing a provider dialog is an intentional action, not an error.
    } on FirebaseAuthException catch (error) {
      if (mounted) _showAuthError(_authMessage(error));
    } catch (_) {
      if (mounted) {
        _showAuthError('Sign-in could not be completed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _submitEmail() async {
    if (!(_emailKey.currentState?.validate() ?? false)) return;
    if (!_registering) {
      await _runAuthentication(
        () => _authService.signInWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
        ),
      );
      return;
    }

    if (_authBusy) return;
    setState(() => _authBusy = true);
    try {
      final credential = await _authService.registerWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      _prefillFromUser(credential.user);
      _goTo(7);
    } on FirebaseAuthException catch (error) {
      if (mounted) _showAuthError(_authMessage(error));
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  void _prefillFromUser(User? user) {
    if (user == null) return;
    if (_emailController.text.isEmpty && user.email != null) {
      _emailController.text = user.email!;
    }
    if (_fullNameController.text.isEmpty && user.displayName != null) {
      _fullNameController.text = user.displayName!;
    }
    if (_displayNameController.text.isEmpty && user.displayName != null) {
      _displayNameController.text = user.displayName!;
    }
    _socialPhotoUrl ??= user.photoURL;
  }

  void _restoreBackendProfile(BackendUser profile) {
    if (profile.displayName?.isNotEmpty ?? false) {
      _fullNameController.text = profile.displayName!;
    }
    if (profile.phone?.isNotEmpty ?? false) {
      _phoneController.text = profile.phone!;
    }
    if (profile.dateOfBirth != null) {
      final date = DateTime.tryParse(profile.dateOfBirth!);
      if (date != null) {
        _dateOfBirthController.text =
            '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      }
    }
    _socialPhotoUrl = profile.photoUrl ?? _socialPhotoUrl;
    if (profile.roles.contains('BUSINESS')) {
      _sellerType = _AccountType.business;
    } else if (profile.roles.contains('SIDE_HUSTLER')) {
      _sellerType = _AccountType.producer;
    } else {
      _sellerType = null;
    }
    _isConsumer = profile.roles.contains('CONSUMER');
    final producer = profile.producerProfile;
    if (producer != null) {
      _displayNameController.text = producer['publicName'] as String? ?? '';
      _introController.text = producer['description'] as String? ?? '';
    }
    final business = profile.businessProfile;
    if (business != null) {
      _displayNameController.text =
          business['publicDisplayName'] as String? ?? '';
      _businessNameController.text =
          business['legalBusinessName'] as String? ?? '';
      _farmNameController.text = business['farmName'] as String? ?? '';
      _businessIdController.text = business['businessId'] as String? ?? '';
      _vatController.text = business['vatNumber'] as String? ?? '';
      _businessType = business['businessType'] as String?;
      _businessAddressController.text =
          business['businessAddress'] as String? ?? '';
      _businessCityController.text = business['city'] as String? ?? '';
      _businessPostalController.text = business['postalCode'] as String? ?? '';
    }
    if (profile.addressLine != null && profile.country != null) {
      _confirmedLocation = ConfirmedLocation(
        addressLine: profile.addressLine!,
        addressUnit: profile.addressUnit,
        city: profile.city ?? '',
        postalCode: profile.postalCode ?? '',
        country: profile.country!,
        latitude: profile.latitude ?? 0,
        longitude: profile.longitude ?? 0,
      );
    }
  }

  int _resumePage(BackendUser profile) {
    if (profile.onboardingStep == 'COMPLETE' ||
        profile.onboardingStep == 'SUBMITTED_FOR_REVIEW') {
      return 6;
    }
    if (profile.onboardingStep == 'BUSINESS_DETAILS_REQUIRED' &&
        profile.phone != null) {
      return 4;
    }
    if (profile.onboardingStep == 'PRODUCER_DETAILS_REQUIRED' ||
        profile.onboardingStep == 'BUSINESS_DETAILS_REQUIRED' ||
        profile.onboardingStep == 'PROFILE_REQUIRED') {
      return 3;
    }
    return 2;
  }

  Future<void> _changeVerificationEmail() async {
    await _authService.signOut();
    _passwordController.clear();
    _confirmPasswordController.clear();
    if (mounted) _goTo(1);
  }

  Future<void> _pickProfilePhoto(ImageSource source) async {
    final photo = await ImagePicker().pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1200,
    );
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    if (mounted) setState(() => _pickedPhotoBytes = bytes);
  }

  void _showPhotoSource() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Choose from photos'),
                    onTap: () {
                      Navigator.pop(context);
                      _pickProfilePhoto(ImageSource.gallery);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: const Text('Take a photo'),
                    onTap: () {
                      Navigator.pop(context);
                      _pickProfilePhoto(ImageSource.camera);
                    },
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Future<void> _checkVerification() async {
    setState(() => _authBusy = true);
    try {
      final verified = await _authService.refreshEmailVerification();
      if (!mounted) return;
      if (verified) {
        _goTo(2);
      } else {
        _showAuthError(
          'Email is not verified yet. Open the link and try again.',
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) _showAuthError(_authMessage(error));
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _resendVerification() async {
    try {
      await _authService.resendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A new verification email was sent.')),
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) _showAuthError(_authMessage(error));
    }
  }

  Future<void> _finishOnboarding() async {
    final user = _authService.currentUser;
    if (user == null) {
      _showAuthError('Your session expired. Please sign in again.');
      _goTo(0);
      return;
    }
    final location = _confirmedLocation;
    if (_effectiveType != _AccountType.consumer && location == null) {
      _showAuthError('Confirm your location before continuing.');
      return;
    }
    setState(() => _authBusy = true);
    try {
      final type = switch (_effectiveType) {
        _AccountType.consumer => 'CONSUMER',
        _AccountType.producer => 'SIDE_HUSTLER',
        _AccountType.business => 'BUSINESS',
      };
      Map<String, dynamic>? seller;
      if (_effectiveType == _AccountType.producer) {
        final sellerLocation = location!;
        seller = {
          'publicName': _displayNameController.text.trim(),
          if (_introController.text.trim().isNotEmpty)
            'description': _introController.text.trim(),
          'productionType': 'Local food producer',
          'address': sellerLocation.formattedAddress,
          'city': sellerLocation.city,
          'postalCode': sellerLocation.postalCode,
          'country': sellerLocation.country,
        };
      } else if (_effectiveType == _AccountType.business) {
        final sellerLocation = location!;
        seller = {
          'publicDisplayName': _displayNameController.text.trim(),
          'legalBusinessName': _businessNameController.text.trim(),
          if (_farmNameController.text.trim().isNotEmpty)
            'farmName': _farmNameController.text.trim(),
          'businessId': _businessIdController.text.trim(),
          if (_vatController.text.trim().isNotEmpty)
            'vatNumber': _vatController.text.trim(),
          'businessType': _businessType,
          'businessAddress': sellerLocation.formattedAddress,
          'city': _businessCityController.text.trim(),
          'postalCode': _businessPostalController.text.trim(),
          'country': sellerLocation.country,
        };
      }
      await _backend.finish(
        displayName: _fullNameController.text.trim(),
        phone: _phoneController.text.trim(),
        dateOfBirth: _isoDate(_dateOfBirthController.text),
        photoUrl: _socialPhotoUrl,
        accountType: type,
        location: location,
        sellerProfile: seller,
      );
      await _progressStore.markComplete(user.uid);
      _draftTimer?.cancel();
      await _draftStore.clear(user.uid);
      if (mounted) _goTo(6);
    } catch (error) {
      if (mounted) _showAuthError(_serverMessage(error));
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      _showAuthError('Enter your email address first.');
      return;
    }
    try {
      await _authService.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent.')),
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) _showAuthError(_authMessage(error));
    }
  }

  void _showAuthError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _authMessage(FirebaseAuthException error) => switch (error.code) {
    'email-already-in-use' =>
      'This email already has an account. Try signing in.',
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'The email or password is incorrect.',
    'weak-password' => 'Choose a stronger password.',
    'network-request-failed' => 'Check your internet connection.',
    'account-exists-with-different-credential' =>
      'This email uses another sign-in method. Use that method first.',
    'operation-not-allowed' =>
      'This sign-in method is not enabled in Firebase yet.',
    _ => error.message ?? 'Authentication failed. Please try again.',
  };

  void _goTo(int page) {
    setState(() => _page = page);
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _continueFromRole() async {
    setState(() => _authBusy = true);
    try {
      await _backend.saveAccountType(_accountTypeCode);
      if (mounted) _goTo(3);
    } catch (error) {
      if (mounted) _showAuthError(_serverMessage(error));
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  String get _accountTypeCode => switch (_effectiveType) {
    _AccountType.consumer => 'CONSUMER',
    _AccountType.producer => 'SIDE_HUSTLER',
    _AccountType.business => 'BUSINESS',
  };

  void _goBack() {
    if (_page == 5 && _sellerType != _AccountType.business) {
      _goTo(3);
      return;
    }
    _goTo(_page - 1);
  }

  Future<void> _continueFromDetails() async {
    if (!(_detailsKey.currentState?.validate() ?? false)) return;
    setState(() => _authBusy = true);
    try {
      await _backend.savePersonalProfile(
        displayName: _fullNameController.text.trim(),
        phone: _phoneController.text.trim(),
        dateOfBirth: _isoDate(_dateOfBirthController.text),
        photoUrl: _socialPhotoUrl,
      );
    } catch (error) {
      if (mounted) _showAuthError(_serverMessage(error));
      return;
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
    if (!mounted) return;
    if (_effectiveType == _AccountType.consumer) {
      _goTo(5);
      return;
    }
    final location = await showModalBottomSheet<ConfirmedLocation>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder:
          (_) => LocationSheet(
            isBusiness: _effectiveType == _AccountType.business,
          ),
    );
    if (location == null || !mounted) return;
    _confirmedLocation = location;
    _scheduleDraftSave();
    _businessAddressController.text = location.formattedAddress;
    _businessCityController.text = location.city;
    _businessPostalController.text = location.postalCode;
    try {
      await _backend.confirmLocation(location);
      if (_effectiveType == _AccountType.producer) {
        await _backend.saveProducerProfile(_producerPayload(location));
      }
    } catch (error) {
      if (mounted) _showAuthError(_serverMessage(error));
      return;
    }
    _goTo(_sellerType == _AccountType.business ? 4 : 5);
  }

  Map<String, dynamic> _producerPayload(ConfirmedLocation location) => {
    'publicName': _displayNameController.text.trim(),
    if (_introController.text.trim().isNotEmpty)
      'description': _introController.text.trim(),
    'productionType': 'Local food producer',
    'address': location.formattedAddress,
    'city': location.city,
    'postalCode': location.postalCode,
    'country': location.country,
  };

  Future<void> _continueFromBusiness() async {
    if (!(_businessKey.currentState?.validate() ?? false)) return;
    final location = _confirmedLocation;
    if (location == null) {
      _showAuthError('Confirm your registered location first.');
      return;
    }
    setState(() => _authBusy = true);
    try {
      await _backend.saveBusinessProfile({
        'publicDisplayName': _displayNameController.text.trim(),
        'legalBusinessName': _businessNameController.text.trim(),
        if (_farmNameController.text.trim().isNotEmpty)
          'farmName': _farmNameController.text.trim(),
        'businessId': _businessIdController.text.trim(),
        if (_vatController.text.trim().isNotEmpty)
          'vatNumber': _vatController.text.trim(),
        'businessType': _businessType,
        'businessAddress': _businessAddressController.text.trim(),
        'city': _businessCityController.text.trim(),
        'postalCode': _businessPostalController.text.trim(),
        'country': location.country,
      });
      if (mounted) _goTo(5);
    } catch (error) {
      if (mounted) _showAuthError(_serverMessage(error));
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  String _isoDate(String value) {
    final p = value.split('/');
    return p.length == 3 ? '${p[2]}-${p[1]}-${p[0]}' : value;
  }

  String _serverMessage(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('DioException [bad response]: ', '');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAF5),
      body: Stack(
        children: [
          Positioned.fill(
            child: SvgPicture.asset(
              'assets/images/auth_farm.svg',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          Positioned.fill(child: _AnimatedFarmSky(animation: _skyController)),
          SafeArea(
            child: Column(
              children: [
                _TopBar(page: _page, onBack: _goBack),
                SizedBox(height: _page == 0 ? 104 : 72),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 500),
                    margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEFFFC),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x160E3522),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        if (_page > 0 && _page < 5)
                          _Progress(current: _progressForPage()),
                        Expanded(
                          child: PageView(
                            controller: _controller,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _WelcomePage(
                                loading: _authBusy,
                                onGoogle:
                                    () => _runAuthentication(
                                      _authService.signInWithGoogle,
                                    ),
                                onEmail: () => _goTo(1),
                              ),
                              _EmailPage(
                                formKey: _emailKey,
                                emailController: _emailController,
                                passwordController: _passwordController,
                                confirmPasswordController:
                                    _confirmPasswordController,
                                registering: _registering,
                                hidePassword: _hidePassword,
                                loading: _authBusy,
                                onMode:
                                    (value) =>
                                        setState(() => _registering = value),
                                onTogglePassword:
                                    () => setState(
                                      () => _hidePassword = !_hidePassword,
                                    ),
                                onForgotPassword: _forgotPassword,
                                onContinue: _submitEmail,
                              ),
                              _AccountTypePage(
                                consumer: _isConsumer,
                                sellerType: _sellerType,
                                onConsumer:
                                    () => setState(() {
                                      if (_isConsumer && _sellerType == null) {
                                        return;
                                      }
                                      _isConsumer = !_isConsumer;
                                      _scheduleDraftSave();
                                    }),
                                onSeller:
                                    (value) => setState(() {
                                      _sellerType =
                                          _sellerType == value ? null : value;
                                      if (_sellerType == null) {
                                        _isConsumer = true;
                                      }
                                      _scheduleDraftSave();
                                    }),
                                onContinue: _continueFromRole,
                              ),
                              _DetailsPage(
                                formKey: _detailsKey,
                                type: _effectiveType,
                                email: _emailController.text,
                                fullNameController: _fullNameController,
                                dateOfBirthController: _dateOfBirthController,
                                displayNameController: _displayNameController,
                                phoneController: _phoneController,
                                introController: _introController,
                                photoUrl: _socialPhotoUrl,
                                photoBytes: _pickedPhotoBytes,
                                onPhoto: _showPhotoSource,
                                onContinue: _continueFromDetails,
                              ),
                              _BusinessPage(
                                formKey: _businessKey,
                                businessNameController: _businessNameController,
                                farmNameController: _farmNameController,
                                businessIdController: _businessIdController,
                                vatController: _vatController,
                                addressController: _businessAddressController,
                                cityController: _businessCityController,
                                postalController: _businessPostalController,
                                businessType: _businessType,
                                onBusinessType:
                                    (value) => setState(() {
                                      _businessType = value;
                                      _scheduleDraftSave();
                                    }),
                                onContinue: _continueFromBusiness,
                              ),
                              _ReviewPage(
                                type: _effectiveType,
                                consumer: _isConsumer,
                                fullName: _fullNameController.text.trim(),
                                phone: _phoneController.text.trim(),
                                publicName: _displayNameController.text.trim(),
                                businessName:
                                    _businessNameController.text.trim(),
                                location: _confirmedLocation,
                                onEditProfile: () => _goTo(3),
                                onEditBusiness:
                                    _effectiveType == _AccountType.business
                                        ? () => _goTo(4)
                                        : null,
                                onFinish: _finishOnboarding,
                                loading: _authBusy,
                              ),
                              _CompletePage(
                                type: _effectiveType,
                                onDone: () => _goTo(0),
                              ),
                              _EmailVerificationPage(
                                email: _emailController.text.trim(),
                                loading: _authBusy,
                                onCheck: _checkVerification,
                                onResend: _resendVerification,
                                onChangeEmail: _changeVerificationEmail,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _progressForPage() {
    if (_page <= 2) return 1;
    if (_page == 3) return 2;
    if (_page == 4) return 3;
    return _reviewPage == 4 ? 4 : 3;
  }
}

class _AnimatedFarmSky extends StatelessWidget {
  const _AnimatedFarmSky({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: animation,
      builder:
          (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final travel = constraints.maxWidth + 110;
              return Stack(
                children: [
                  Positioned(
                    right: 40,
                    top: 116 - (animation.value * 18),
                    child: _SunGlow(pulse: animation.value),
                  ),
                  Positioned(
                    left: -90 + (travel * animation.value),
                    top: 112,
                    child: const _Cloud(width: 72, opacity: .82),
                  ),
                  Positioned(
                    right: -65 + (travel * animation.value),
                    top: 174,
                    child: const _Cloud(width: 48, opacity: .65),
                  ),
                ],
              );
            },
          ),
    ),
  );
}

class _SunGlow extends StatelessWidget {
  const _SunGlow({required this.pulse});
  final double pulse;

  @override
  Widget build(BuildContext context) => Container(
    width: 54 + (pulse * 5),
    height: 54 + (pulse * 5),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: _gold,
      boxShadow: [
        BoxShadow(
          color: _gold.withValues(alpha: .22 + (pulse * .12)),
          blurRadius: 18 + (pulse * 14),
          spreadRadius: 7 + (pulse * 5),
        ),
      ],
    ),
  );
}

class _Cloud extends StatelessWidget {
  const _Cloud({required this.width, required this.opacity});
  final double width;
  final double opacity;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: opacity,
    child: Icon(
      Icons.cloud_rounded,
      size: width,
      color: Colors.white,
      shadows: const [Shadow(color: Color(0x11000000), blurRadius: 8)],
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.page, required this.onBack});
  final int page;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Row(
      children: [
        if (page > 0 && page < 6)
          IconButton.filledTonal(
            onPressed: onBack,
            style: IconButton.styleFrom(backgroundColor: Colors.white),
            icon: const Icon(Icons.arrow_back_rounded),
          )
        else
          const SizedBox(width: 48),
        const Spacer(),
        Image.asset('assets/images/logo_transparent.png', width: 108),
        const Spacer(),
        const SizedBox(width: 48),
      ],
    ),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
    child: Column(
      children: [
        Row(
          children: [
            Text(
              'YOUR SETUP',
              style: TextStyle(
                color: _green.withValues(alpha: .9),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            const Spacer(),
            Text(
              '$current of 4',
              style: const TextStyle(
                color: _muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(
            4,
            (index) => Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                height: 5,
                margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
                decoration: BoxDecoration(
                  color: index < current ? _green : _line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({
    required this.loading,
    required this.onGoogle,
    required this.onEmail,
  });
  final bool loading;
  final VoidCallback onGoogle;
  final VoidCallback onEmail;

  @override
  Widget build(BuildContext context) => _ScrollPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: _Eyebrow('WELCOME')),
        const Text(
          'Fresh food near you',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ink,
            fontSize: 28,
            height: 1.1,
            fontWeight: FontWeight.w900,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 9),
        const Text(
          'One account for discovering, making and selling local food.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 22),
        _ProviderButton(
          mark: 'G',
          label: 'Continue with Google',
          loading: loading,
          onPressed: onGoogle,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: Divider(color: _line)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: TextStyle(color: _muted)),
            ),
            const Expanded(child: Divider(color: _line)),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: loading ? null : onEmail,
          icon: const Icon(Icons.mail_outline_rounded),
          label: const Text('Continue with email'),
          style: _outlineStyle,
        ),
        const SizedBox(height: 14),
        const Text(
          'Secure sign-in • your saved setup resumes automatically',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 11.5),
        ),
      ],
    ),
  );
}

class _EmailPage extends StatelessWidget {
  const _EmailPage({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.registering,
    required this.hidePassword,
    required this.loading,
    required this.onMode,
    required this.onTogglePassword,
    required this.onForgotPassword,
    required this.onContinue,
  });
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool registering;
  final bool hidePassword;
  final bool loading;
  final ValueChanged<bool> onMode;
  final VoidCallback onTogglePassword;
  final VoidCallback onForgotPassword;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => _ScrollPage(
    child: Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Eyebrow('YOUR ACCOUNT'),
          Text(
            registering ? 'Create your account' : 'Welcome back',
            style: _title,
          ),
          const SizedBox(height: 6),
          Text(
            registering
                ? 'A few details now, then make FRSH yours.'
                : 'Use the email and password you registered with.',
            style: const TextStyle(color: _muted),
          ),
          const SizedBox(height: 18),
          _Segmented(
            left: 'Create account',
            right: 'Sign in',
            leftSelected: registering,
            onLeft: () => onMode(true),
            onRight: () => onMode(false),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: emailController,
            enabled: !loading,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            validator:
                (value) =>
                    value != null && value.contains('@')
                        ? null
                        : 'Enter a valid email address.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: passwordController,
            enabled: !loading,
            obscureText: hidePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                onPressed: onTogglePassword,
                icon: Icon(
                  hidePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator:
                (value) =>
                    (value?.length ?? 0) >= 8
                        ? null
                        : 'Use at least 8 characters.',
          ),
          if (registering) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: confirmPasswordController,
              enabled: !loading,
              obscureText: hidePassword,
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: Icon(Icons.lock_reset_rounded),
              ),
              validator:
                  (value) =>
                      value == passwordController.text
                          ? null
                          : 'Passwords do not match.',
            ),
          ],
          if (!registering)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: loading ? null : onForgotPassword,
                child: const Text('Forgot password?'),
              ),
            ),
          const SizedBox(height: 20),
          _PrimaryButton(
            label: registering ? 'Continue' : 'Sign in',
            onPressed: onContinue,
            loading: loading,
          ),
        ],
      ),
    ),
  );
}

class _AccountTypePage extends StatelessWidget {
  const _AccountTypePage({
    required this.consumer,
    required this.sellerType,
    required this.onConsumer,
    required this.onSeller,
    required this.onContinue,
  });
  final bool consumer;
  final _AccountType? sellerType;
  final VoidCallback onConsumer;
  final ValueChanged<_AccountType> onSeller;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => _ScrollPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Eyebrow('STEP 1 OF 4'),
        const Text('How will you use FRSH?', style: _title),
        const SizedBox(height: 6),
        const Text(
          'You can also be a consumer. Choose only one type of seller profile.',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 18),
        _TypeCard(
          selected: consumer,
          icon: Icons.shopping_basket_outlined,
          accent: const Color(0xFFDCEBDD),
          title: 'Consumer',
          subtitle: 'Discover fresh food and trusted makers nearby.',
          onTap: onConsumer,
        ),
        const SizedBox(height: 10),
        _TypeCard(
          selected: sellerType == _AccountType.producer,
          icon: Icons.spa_outlined,
          accent: const Color(0xFFFFF2CC),
          title: 'Side-hustle producer',
          subtitle: 'Sell small-batch, seasonal or homemade products.',
          badge: 'INDIVIDUAL',
          onTap: () => onSeller(_AccountType.producer),
        ),
        const SizedBox(height: 10),
        _TypeCard(
          selected: sellerType == _AccountType.business,
          icon: Icons.storefront_outlined,
          accent: const Color(0xFFDDE8F4),
          title: 'Registered business',
          subtitle: 'Build a verified storefront for your farm or company.',
          badge: 'BUSINESS',
          onTap: () => onSeller(_AccountType.business),
        ),
        const SizedBox(height: 18),
        _PrimaryButton(label: 'Continue', onPressed: onContinue),
      ],
    ),
  );
}

class _EmailVerificationPage extends StatelessWidget {
  const _EmailVerificationPage({
    required this.email,
    required this.loading,
    required this.onCheck,
    required this.onResend,
    required this.onChangeEmail,
  });
  final String email;
  final bool loading;
  final VoidCallback onCheck;
  final VoidCallback onResend;
  final VoidCallback onChangeEmail;

  @override
  Widget build(BuildContext context) => _ScrollPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: _mist,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mark_email_unread_outlined,
              color: _green,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Verify your email',
          textAlign: TextAlign.center,
          style: _title,
        ),
        const SizedBox(height: 8),
        Text(
          'We sent a verification link to\n$email',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, height: 1.4),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8F1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'Open the link in your email, then return here. Check your spam folder if it does not arrive.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
        const SizedBox(height: 20),
        _PrimaryButton(
          label: 'I have verified my email',
          onPressed: onCheck,
          loading: loading,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: loading ? null : onResend,
          child: const Text('Resend verification email'),
        ),
        TextButton(
          onPressed: loading ? null : onChangeEmail,
          child: const Text('Use a different email'),
        ),
      ],
    ),
  );
}

class _DetailsPage extends StatelessWidget {
  const _DetailsPage({
    required this.formKey,
    required this.type,
    required this.email,
    required this.fullNameController,
    required this.dateOfBirthController,
    required this.displayNameController,
    required this.phoneController,
    required this.introController,
    required this.photoUrl,
    required this.photoBytes,
    required this.onPhoto,
    required this.onContinue,
  });
  final GlobalKey<FormState> formKey;
  final _AccountType type;
  final String email;
  final TextEditingController fullNameController;
  final TextEditingController dateOfBirthController;
  final TextEditingController displayNameController;
  final TextEditingController phoneController;
  final TextEditingController introController;
  final String? photoUrl;
  final Uint8List? photoBytes;
  final VoidCallback onPhoto;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final isSeller = type != _AccountType.consumer;
    return _ScrollPage(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Eyebrow('STEP 2 OF 4'),
            Text(
              isSeller ? 'Create your public profile' : 'Tell us about you',
              style: _title,
            ),
            const SizedBox(height: 6),
            Text(
              isSeller
                  ? 'This is how local customers will recognise you.'
                  : 'We use this to make your experience feel local.',
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 18),
            _PhotoPicker(
              photoUrl: photoUrl,
              photoBytes: photoBytes,
              onTap: onPhoto,
            ),
            const SizedBox(height: 16),
            _RequiredField(label: 'Full name', controller: fullNameController),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Verified email address',
                prefixIcon: Icon(Icons.verified_outlined),
              ),
              child: Text(email),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: dateOfBirthController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Date of birth *',
                hintText: 'Select date',
                prefixIcon: Icon(Icons.cake_outlined),
              ),
              onTap: () async {
                final now = DateTime.now();
                final selected = await showDatePicker(
                  context: context,
                  initialDate: DateTime(now.year - 18),
                  firstDate: DateTime(1900),
                  lastDate: DateTime(now.year - 18, now.month, now.day),
                );
                if (selected != null) {
                  dateOfBirthController.text =
                      '${selected.day.toString().padLeft(2, '0')}/'
                      '${selected.month.toString().padLeft(2, '0')}/'
                      '${selected.year}';
                }
              },
              validator:
                  (value) =>
                      value == null || value.isEmpty
                          ? 'Select your date of birth.'
                          : null,
            ),
            const SizedBox(height: 12),
            if (isSeller) ...[
              _RequiredField(
                label: 'Display name (public)',
                controller: displayNameController,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: introController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Short introduction',
                  hintText: 'What do you make or grow?',
                ),
              ),
              const SizedBox(height: 12),
            ],
            _InternationalPhoneField(controller: phoneController),
            const SizedBox(height: 20),
            _PrimaryButton(label: 'Continue', onPressed: onContinue),
          ],
        ),
      ),
    );
  }
}

class _BusinessPage extends StatelessWidget {
  const _BusinessPage({
    required this.formKey,
    required this.businessNameController,
    required this.farmNameController,
    required this.businessIdController,
    required this.vatController,
    required this.addressController,
    required this.cityController,
    required this.postalController,
    required this.businessType,
    required this.onBusinessType,
    required this.onContinue,
  });
  final GlobalKey<FormState> formKey;
  final TextEditingController businessNameController;
  final TextEditingController farmNameController;
  final TextEditingController businessIdController;
  final TextEditingController vatController;
  final TextEditingController addressController;
  final TextEditingController cityController;
  final TextEditingController postalController;
  final String? businessType;
  final ValueChanged<String?> onBusinessType;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => _ScrollPage(
    child: Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Eyebrow('STEP 3 OF 4'),
          const Text('Business details', style: _title),
          const SizedBox(height: 6),
          const Text(
            'These details help us verify your storefront. Only your public name and address area are shown.',
            style: TextStyle(color: _muted, height: 1.4),
          ),
          const SizedBox(height: 18),
          _RequiredField(
            label: 'Business name',
            controller: businessNameController,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: farmNameController,
            decoration: const InputDecoration(labelText: 'Farm name'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RequiredField(
                  label: 'Business ID',
                  controller: businessIdController,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: vatController,
                  decoration: const InputDecoration(labelText: 'VAT number'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: businessType,
            decoration: const InputDecoration(labelText: 'Business type *'),
            items: const [
              DropdownMenuItem(value: 'farm', child: Text('Farm')),
              DropdownMenuItem(value: 'food', child: Text('Food producer')),
              DropdownMenuItem(value: 'retail', child: Text('Retailer')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: onBusinessType,
            validator:
                (value) => value == null ? 'Select a business type.' : null,
          ),
          const SizedBox(height: 12),
          _RequiredField(
            label: 'Business address',
            controller: addressController,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RequiredField(
                  label: 'City',
                  controller: cityController,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RequiredField(
                  label: 'Zip code',
                  controller: postalController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _PrimaryButton(label: 'Review application', onPressed: onContinue),
        ],
      ),
    ),
  );
}

class _ReviewPage extends StatelessWidget {
  const _ReviewPage({
    required this.type,
    required this.consumer,
    required this.fullName,
    required this.phone,
    required this.publicName,
    required this.businessName,
    required this.location,
    required this.onEditProfile,
    required this.onEditBusiness,
    required this.onFinish,
    required this.loading,
  });
  final _AccountType type;
  final bool consumer;
  final String fullName;
  final String phone;
  final String publicName;
  final String businessName;
  final ConfirmedLocation? location;
  final VoidCallback onEditProfile;
  final VoidCallback? onEditBusiness;
  final VoidCallback onFinish;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final sellerTitle = switch (type) {
      _AccountType.consumer => 'Consumer',
      _AccountType.producer => 'Side-hustle producer',
      _AccountType.business => 'Registered business',
    };
    final title =
        consumer && type != _AccountType.consumer
            ? 'Consumer + $sellerTitle'
            : sellerTitle;
    return _ScrollPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Eyebrow('FINAL STEP'),
          const Text('Everything looks fresh', style: _title),
          const SizedBox(height: 6),
          const Text(
            'Confirm what we saved. You can edit anything before continuing.',
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 22),
          _SummaryTile(
            icon: Icons.account_circle_outlined,
            title: 'Account type',
            value: title,
          ),
          const SizedBox(height: 10),
          _SummaryTile(
            icon: Icons.badge_outlined,
            title: fullName,
            value: phone,
            onEdit: onEditProfile,
          ),
          if (type != _AccountType.consumer) ...[
            const SizedBox(height: 10),
            _SummaryTile(
              icon:
                  type == _AccountType.business
                      ? Icons.storefront_outlined
                      : Icons.spa_outlined,
              title: 'Public identity',
              value: type == _AccountType.business ? businessName : publicName,
              onEdit: onEditBusiness ?? onEditProfile,
            ),
            if (location != null) ...[
              const SizedBox(height: 10),
              _SummaryTile(
                icon: Icons.location_on_outlined,
                title: 'Registered location',
                value: [
                  location!.addressLine,
                  location!.addressUnit,
                  location!.postalCode,
                  location!.city,
                  location!.country,
                ].where((value) => value?.isNotEmpty == true).join(', '),
                onEdit: onEditProfile,
              ),
            ],
            const SizedBox(height: 10),
            const _SummaryTile(
              icon: Icons.verified_user_outlined,
              title: 'Seller verification',
              value: 'Available later from your profile',
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _mist,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, color: _green, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your private account and verification details are never displayed publicly.',
                    style: TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _PrimaryButton(
            label: 'Create my account',
            onPressed: onFinish,
            loading: loading,
          ),
          const SizedBox(height: 10),
          const Text(
            'By continuing, you agree to our Terms and Privacy Policy.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CompletePage extends StatelessWidget {
  const _CompletePage({required this.type, required this.onDone});
  final _AccountType type;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => _PagePadding(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: const BoxDecoration(
                  color: _mist,
                  shape: BoxShape.circle,
                ),
              ),
              const CircleAvatar(
                radius: 36,
                backgroundColor: Color(0xFFDCEBDD),
                child: Icon(Icons.check_rounded, color: _green, size: 40),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Welcome to FRSH nearby!',
          textAlign: TextAlign.center,
          style: _title,
        ),
        const SizedBox(height: 8),
        Text(
          type == _AccountType.consumer
              ? 'Your local food journey starts now.'
              : 'Your profile is ready. You can apply for seller verification later from your profile.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, height: 1.4),
        ),
        const SizedBox(height: 28),
        _PrimaryButton(label: 'Explore FRSH', onPressed: onDone),
      ],
    ),
  );
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.photoUrl,
    required this.photoBytes,
    required this.onTap,
  });
  final String? photoUrl;
  final Uint8List? photoBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: _mist,
                backgroundImage:
                    photoBytes != null
                        ? MemoryImage(photoBytes!)
                        : photoUrl == null
                        ? null
                        : NetworkImage(photoUrl!),
                child:
                    photoBytes == null && photoUrl == null
                        ? const Icon(
                          Icons.person_outline_rounded,
                          color: _green,
                          size: 38,
                        )
                        : null,
              ),
              Positioned(
                right: -4,
                bottom: -2,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            photoBytes != null || photoUrl != null
                ? 'Change profile photo'
                : 'Add profile photo · optional',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _RequiredField extends StatelessWidget {
  const _RequiredField({required this.label, this.controller});
  final String label;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: '$label *'),
    validator:
        (value) =>
            value == null || value.trim().isEmpty
                ? '$label is required.'
                : null,
  );
}

class _InternationalPhoneField extends StatefulWidget {
  const _InternationalPhoneField({required this.controller});
  final TextEditingController controller;

  @override
  State<_InternationalPhoneField> createState() =>
      _InternationalPhoneFieldState();
}

class _InternationalPhoneFieldState extends State<_InternationalPhoneField> {
  late Country _country;
  final _national = TextEditingController();
  bool _writingCanonical = false;

  @override
  void initState() {
    super.initState();
    final locales = WidgetsBinding.instance.platformDispatcher.locales;
    final region =
        locales
            .map((locale) => locale.countryCode?.toUpperCase())
            .whereType<String>()
            .where((code) => code.isNotEmpty && code != 'US')
            .firstOrNull;

    // Many browsers report en-US even when the user is physically elsewhere.
    // FRSH Nearby currently launches in Finland, so do not turn that generic
    // browser fallback into an incorrect +1 default. The picker remains
    // available for users whose calling code differs from their device region.
    _country = Country.tryParse(region ?? 'FI') ?? Country.parse('FI');
    widget.controller.addListener(_hydrateFromCanonical);
    _hydrateFromCanonical();
    _sync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_hydrateFromCanonical);
    _national.dispose();
    super.dispose();
  }

  void _hydrateFromCanonical() {
    if (_writingCanonical || _national.text.isNotEmpty) return;
    final canonical = widget.controller.text.trim();
    if (!canonical.startsWith('+')) return;
    final countries =
        CountryService()
            .getAll()
            .where((item) => canonical.startsWith('+${item.phoneCode}'))
            .toList()
          ..sort((a, b) => b.phoneCode.length.compareTo(a.phoneCode.length));
    if (countries.isEmpty) return;
    final selected = countries.first;
    final national = canonical.substring(selected.phoneCode.length + 1);
    if (mounted) {
      setState(() => _country = selected);
      _national.text = national;
    }
  }

  void _sync() {
    final number = _national.text
        .replaceAll(RegExp(r'\D'), '')
        .replaceFirst(RegExp(r'^0+'), '');
    _writingCanonical = true;
    widget.controller.text = '+${_country.phoneCode}$number';
    _writingCanonical = false;
  }

  void _chooseCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      countryListTheme: const CountryListThemeData(
        bottomSheetHeight: 560,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        inputDecoration: InputDecoration(
          labelText: 'Search country or code',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      onSelect: (country) {
        setState(() => _country = country);
        _sync();
      },
    );
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: _national,
    keyboardType: TextInputType.phone,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    onChanged: (_) => _sync(),
    decoration: InputDecoration(
      labelText: 'Phone number *',
      hintText: _country.example.isEmpty ? 'Phone number' : _country.example,
      prefixIconConstraints: const BoxConstraints(minWidth: 108),
      prefixIcon: InkWell(
        onTap: _chooseCountry,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_country.flagEmoji, style: const TextStyle(fontSize: 21)),
              const SizedBox(width: 6),
              Text('+${_country.phoneCode}'),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
      ),
    ),
    validator: (_) {
      final value = widget.controller.text;
      return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value)
          ? null
          : 'Enter a valid phone number.';
    },
  );
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.selected,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });
  final bool selected;
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF7FBF6) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _green : _line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: _deepGreen, size: 27),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? _green : _line,
            ),
          ],
        ),
      ),
    ),
  );
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.title,
    required this.value,
    this.onEdit,
  });
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F8F1),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFDCEBDD),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: _green),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: _muted, fontSize: 12)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        if (onEdit != null)
          TextButton(onPressed: onEdit, child: const Text('Edit'))
        else
          const Icon(Icons.check_circle_rounded, color: _green, size: 20),
      ],
    ),
  );
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.left,
    required this.right,
    required this.leftSelected,
    required this.onLeft,
    required this.onRight,
  });
  final String left;
  final String right;
  final bool leftSelected;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: _mist,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      children: [
        Expanded(
          child: _Segment(label: left, selected: leftSelected, onTap: onLeft),
        ),
        Expanded(
          child: _Segment(
            label: right,
            selected: !leftSelected,
            onTap: onRight,
          ),
        ),
      ],
    ),
  );
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: selected ? _ink : _muted,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.mark,
    required this.label,
    required this.loading,
    required this.onPressed,
  });
  final String mark;
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: loading ? null : onPressed,
    style: _outlineStyle,
    child: Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            mark,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
        Expanded(child: Text(label, textAlign: TextAlign.center)),
        const SizedBox(width: 28),
      ],
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: loading ? null : onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      backgroundColor: _green,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
    ),
    child:
        loading
            ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
            : Text(label),
  );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: _green,
        fontSize: 11,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _PagePadding extends StatelessWidget {
  const _PagePadding({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(20), child: child);
}

class _ScrollPage extends StatelessWidget {
  const _ScrollPage({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
    child: child,
  );
}

const _title = TextStyle(
  color: _ink,
  fontSize: 24,
  height: 1.15,
  fontWeight: FontWeight.w900,
);

final _outlineStyle = OutlinedButton.styleFrom(
  minimumSize: const Size.fromHeight(50),
  foregroundColor: _ink,
  side: const BorderSide(color: _line),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  textStyle: const TextStyle(fontWeight: FontWeight.w700),
);
