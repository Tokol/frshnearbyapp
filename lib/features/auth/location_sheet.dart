import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'backend_service.dart';

class LocationSheet extends StatefulWidget {
  const LocationSheet({required this.isBusiness, super.key});
  final bool isBusiness;
  @override
  State<LocationSheet> createState() => _LocationSheetState();
}

class _SellerLocationVisual extends StatelessWidget {
  const _SellerLocationVisual({required this.isBusiness});
  final bool isBusiness;

  @override
  Widget build(BuildContext context) => Container(
    height: 118,
    decoration: BoxDecoration(
      color: const Color(0xFFF0F6E9),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFD9E6D1)),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          right: -18,
          bottom: -34,
          child: Container(
            width: 130,
            height: 130,
            decoration: const BoxDecoration(
              color: Color(0xFFDDECD7),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Row(
          children: [
            const SizedBox(width: 22),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x160E3522),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    isBusiness
                        ? Icons.storefront_rounded
                        : Icons.agriculture_rounded,
                    color: const Color(0xFF2F6B45),
                    size: 37,
                  ),
                  const Positioned(
                    right: 7,
                    bottom: 7,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: Color(0xFFE9CD7A),
                      child: Icon(
                        Icons.location_on_rounded,
                        size: 15,
                        color: Color(0xFF184D31),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isBusiness ? 'Business location' : 'Seller location',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF183326),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'This location powers nearby discovery.',
                    style: TextStyle(color: Color(0xFF647267), fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
          ],
        ),
      ],
    ),
  );
}

class _LocationSheetState extends State<LocationSheet> {
  final _key = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _addressUnit = TextEditingController();
  final _city = TextEditingController();
  final _postal = TextEditingController();
  final _country = TextEditingController();
  bool _busy = false;
  double? _lat;
  double? _lng;
  String? _detectedAddressSignature;

  @override
  void dispose() {
    _address.dispose();
    _addressUnit.dispose();
    _city.dispose();
    _postal.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    setState(() => _busy = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError(
          'Turn on location services, or enter your address manually.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError(
          'Location permission was not granted. Enter your address manually.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _lat = position.latitude;
      _lng = position.longitude;
      if (kIsWeb) {
        await _reverseGeocodeWeb();
      } else {
        final places = await placemarkFromCoordinates(_lat!, _lng!);
        if (places.isNotEmpty) {
          final p = places.first;
          _address.text = [
            p.street,
            p.subLocality,
          ].where((v) => v != null && v.isNotEmpty).join(', ');
          _city.text = p.locality ?? p.administrativeArea ?? '';
          _postal.text = p.postalCode ?? '';
          _country.text = p.country ?? '';
          _detectedAddressSignature = _addressSignature;
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reverseGeocodeWeb() async {
    const endpoint = String.fromEnvironment(
      'FRSH_REVERSE_GEOCODE_URL',
      defaultValue: 'https://nominatim.openstreetmap.org/reverse',
    );
    final response = await Dio().get<Map<String, dynamic>>(
      endpoint,
      queryParameters: {
        'format': 'jsonv2',
        'lat': _lat,
        'lon': _lng,
        'zoom': 18,
        'addressdetails': 1,
        'layer': 'address',
      },
      options: Options(
        headers: {'Accept': 'application/json'},
        receiveTimeout: const Duration(seconds: 12),
      ),
    );
    final address = response.data?['address'] as Map<String, dynamic>?;
    if (address == null) return;
    final house = address['house_number'] as String?;
    final road =
        address['road'] as String? ??
        address['pedestrian'] as String? ??
        address['residential'] as String?;
    _address.text = [
      house,
      road,
    ].where((value) => value?.isNotEmpty == true).join(' ');
    _city.text =
        address['city'] as String? ??
        address['town'] as String? ??
        address['village'] as String? ??
        address['municipality'] as String? ??
        '';
    _postal.text = address['postcode'] as String? ?? '';
    _country.text = address['country'] as String? ?? '';
    _detectedAddressSignature = _addressSignature;
  }

  String get _addressSignature => [
    _address.text.trim().toLowerCase(),
    _postal.text.trim().toLowerCase(),
    _city.text.trim().toLowerCase(),
    _country.text.trim().toLowerCase(),
  ].join('|');

  Future<void> _resolveEnteredAddress() async {
    if (_detectedAddressSignature == _addressSignature &&
        _lat != null &&
        _lng != null) {
      return;
    }
    final query = [
      _address.text.trim(),
      _postal.text.trim(),
      _city.text.trim(),
      _country.text.trim(),
    ].where((value) => value.isNotEmpty).join(', ');
    if (kIsWeb) {
      const endpoint = String.fromEnvironment(
        'FRSH_GEOCODE_SEARCH_URL',
        defaultValue: 'https://nominatim.openstreetmap.org/search',
      );
      final response = await Dio().get<List<dynamic>>(
        endpoint,
        queryParameters: {
          'format': 'jsonv2',
          'q': query,
          'limit': 1,
          'addressdetails': 1,
        },
        options: Options(
          headers: {'Accept': 'application/json'},
          receiveTimeout: const Duration(seconds: 12),
        ),
      );
      final results = response.data;
      if (results == null || results.isEmpty) {
        throw StateError(
          'We could not locate this address. Check it and try again.',
        );
      }
      final result = results.first as Map<String, dynamic>;
      _lat = double.tryParse(result['lat'] as String? ?? '');
      _lng = double.tryParse(result['lon'] as String? ?? '');
    } else {
      final results = await locationFromAddress(query);
      if (results.isEmpty) {
        throw StateError(
          'We could not locate this address. Check it and try again.',
        );
      }
      _lat = results.first.latitude;
      _lng = results.first.longitude;
    }
    if (_lat == null || _lng == null) {
      throw StateError(
        'We could not locate this address. Check it and try again.',
      );
    }
  }

  Future<void> _confirm() async {
    if (!(_key.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await _resolveEnteredAddress();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      ConfirmedLocation(
        addressLine: _address.text.trim(),
        addressUnit:
            _addressUnit.text.trim().isEmpty ? null : _addressUnit.text.trim(),
        city: _city.text.trim(),
        postalCode: _postal.text.trim(),
        country: _country.text.trim(),
        latitude: _lat ?? 0,
        longitude: _lng ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isBusiness
                              ? 'Where is your business?'
                              : 'Where do you make or sell?',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.isBusiness
                              ? 'Add the storefront, farm or operating location customers should discover.'
                              : 'Add your farm, kitchen, pickup point or production location.',
                          style: const TextStyle(
                            color: Color(0xFF647267),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SellerLocationVisual(isBusiness: widget.isBusiness),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : _detect,
                icon:
                    _busy
                        ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.my_location),
                label: Text(
                  _busy
                      ? 'Finding this address…'
                      : 'Suggest from my current position',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Optional shortcut only. Edit the address below if you are not currently at the seller location.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF647267),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Street address and number *',
                  hintText: 'For example: Konejakatu 9',
                ),
                validator: _required,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _addressUnit,
                decoration: const InputDecoration(
                  labelText: 'Building, block, unit or floor',
                  hintText: 'For example: Building Q4, unit A 9',
                  prefixIcon: Icon(Icons.apartment_outlined),
                ),
              ),
              if (kIsWeb) ...[
                const SizedBox(height: 8),
                const Text(
                  'Address lookup © OpenStreetMap contributors. Please confirm the street before saving.',
                  style: TextStyle(fontSize: 10, color: Color(0xFF647267)),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _postal,
                      decoration: const InputDecoration(
                        labelText: 'Postal code *',
                      ),
                      validator: _required,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _city,
                      decoration: const InputDecoration(labelText: 'City *'),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _country,
                decoration: const InputDecoration(labelText: 'Country *'),
                validator: _required,
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : _confirm,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Confirm seller location'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}
