import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'backend_service.dart';

class LocationSheet extends StatefulWidget {
  const LocationSheet({super.key});
  @override
  State<LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<LocationSheet> {
  final _key = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _postal = TextEditingController();
  final _country = TextEditingController();
  bool _busy = false;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  @override
  void dispose() {
    _address.dispose();
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
  }

  void _confirm() {
    if (!(_key.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      ConfirmedLocation(
        addressLine: _address.text.trim(),
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirm your location',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Used to show fresh food near you. You can change it.',
                          style: TextStyle(color: Color(0xFF647267)),
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
                  _busy ? 'Detecting location…' : 'Use my current location',
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Street address *',
                ),
                validator: _required,
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
                onPressed: _confirm,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Confirm this address'),
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
