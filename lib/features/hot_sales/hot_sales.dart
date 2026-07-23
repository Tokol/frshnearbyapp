// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/localized_text.dart' show localizeText;
import '../notifications/device_installation_store.dart';

const _green = Color(0xFF2F6B45);
const _ink = Color(0xFF1B2A20);
const _muted = Color(0xFF66735F);
const _surface = Color(0xFFF1F6ED);

class _Ring {
  const _Ring({
    required this.id,
    required this.name,
    required this.region,
    required this.municipality,
    required this.address,
    required this.priority,
    required this.schedule,
  });
  final String id;
  final String name;
  final String region;
  final String municipality;
  final String address;
  final int priority;
  final String schedule;

  factory _Ring.fromJson(Map<String, dynamic> json) {
    final raw = json['schedule'] as Map<String, dynamic>?;
    final schedule =
        raw == null
            ? ''
            : '${raw['frequency'] == 'BIWEEKLY' ? 'Every other week' : 'Every week'} · ${_weekday(raw['weekday'] as int? ?? 1)} ${raw['startTime']}–${raw['endTime']}';
    return _Ring(
      id: json['id'] as String,
      name: json['name'] as String,
      region: json['regionName'] as String? ?? '',
      municipality: json['municipality'] as String,
      address: [
        json['addressLine'],
        json['postalCode'],
      ].whereType<String>().where((v) => v.isNotEmpty).join(', '),
      priority: json['priority'] as int? ?? 2,
      schedule: schedule,
    );
  }
}

String _weekday(int value) =>
    const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][value.clamp(1, 7) - 1];

String _scheduleLabel(BuildContext context, String schedule) {
  if (schedule.isEmpty) return '';
  final parts = schedule.split(' · ');
  if (parts.length != 2) return schedule;
  final time = parts[1].split(' ');
  if (time.length < 2) return schedule;
  return '${localizeText(context, parts[0])} · '
      '${localizeText(context, time.first)} ${time.skip(1).join(' ')}';
}

class _Sale {
  const _Sale(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get originalTitle => json['originalTitle'] as String;
  String get originalDescription => json['description'] as String;
  String get originalLanguage =>
      json['detectedLanguage'] as String? ?? json['originalLanguage'] as String;
  Map<String, dynamic>? translation(String locale) =>
      (json['translations'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where(
            (item) => item['locale'] == locale && item['status'] == 'COMPLETED',
          )
          .firstOrNull;
  String title(String locale) =>
      translation(locale)?['title'] as String? ?? originalTitle;
  String description(String locale) =>
      translation(locale)?['description'] as String? ?? originalDescription;
  bool isTranslated(String locale) =>
      locale != originalLanguage && translation(locale) != null;
  double get quantity => (json['quantity'] as num).toDouble();
  int get priceCents => json['priceCents'] as int;
  String get unit => json['unit'] as String;
  Uint8List get image => base64Decode(json['imageBase64'] as String);
}

class _HotSalesApi {
  _HotSalesApi()
    : _dio = Dio(
        BaseOptions(
          baseUrl: const String.fromEnvironment(
            'FRSH_API_URL',
            defaultValue: 'https://frshnearby-api.onrender.com/graphql',
          ),
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
  final Dio _dio;
  final DeviceInstallationStore _installations = DeviceInstallationStore();

  Future<Map<String, dynamic>> send(
    String query, [
    Map<String, dynamic> variables = const {},
  ]) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw StateError('Please sign in again.');
    final response = await _dio.post<Map<String, dynamic>>(
      '',
      data: {'query': query, 'variables': variables},
      options: Options(
        headers: {
          'authorization': 'Bearer $token',
          'x-frsh-installation-id': await _installations.id(),
        },
        validateStatus: (_) => true,
      ),
    );
    final body = response.data ?? const {};
    final errors = body['errors'] as List<dynamic>?;
    if (errors?.isNotEmpty == true)
      throw StateError(
        (errors!.first as Map<String, dynamic>)['message'] as String? ??
            'Server request failed.',
      );
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw StateError('Server rejected the request (HTTP $status).');
    }
    return body['data'] as Map<String, dynamic>;
  }

  Future<List<_Sale>> sales() async {
    final data = await send(
      'query { myHotSales { id categoryKey originalLanguage detectedLanguage originalTitle description productionDetail unit priceCents quantity producedAt availableAtFarm status imageMimeType imageBase64 translations { locale title description productionDetail status provider model } rekoRings { id name municipality regionName } } }',
    );
    return (data['myHotSales'] as List<dynamic>)
        .map((v) => _Sale(v as Map<String, dynamic>))
        .toList();
  }

  Future<List<_Ring>> rings() async {
    final data = await send(
      'query { availableRekoRings { id name regionName municipality addressLine postalCode priority schedule { frequency weekday startTime endTime timezone } } }',
    );
    return (data['availableRekoRings'] as List<dynamic>)
        .map((v) => _Ring.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  Future<void> create(Map<String, dynamic> input) => send(
    'mutation(\$input: CreateHotSaleInput!) { createHotSale(input: \$input) { id } }',
    {'input': input},
  );
  Future<void> quantity(String id, double value) => send(
    'mutation(\$input: HotSaleQuantityInput!) { setHotSaleQuantity(input: \$input) { id } }',
    {
      'input': {'id': id, 'quantity': value},
    },
  );
}

class HotSalesScreen extends StatefulWidget {
  const HotSalesScreen({super.key});
  @override
  State<HotSalesScreen> createState() => _HotSalesScreenState();
}

class _HotSalesScreenState extends State<HotSalesScreen> {
  final _api = _HotSalesApi();
  late Future<List<_Sale>> _sales = _api.sales();

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(localizeText(context, 'Hot Sales')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: Text(localizeText(context, 'Add product')),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<_Sale>>(
        future: _sales,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return _Message(
              icon: Icons.cloud_off_outlined,
              text:
                  '${localizeText(context, 'Could not load Hot Sales')}\n${snapshot.error}',
            );
          final sales = snapshot.data ?? const [];
          if (sales.isEmpty)
            return _Message(
              icon: Icons.local_offer_outlined,
              text: localizeText(
                context,
                'Add your first seasonal product for nearby customers.',
              ),
            );
          return ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: sales.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder:
                (_, index) => _SaleCard(
                  sale: sales[index],
                  language: language,
                  onChanged: (value) async {
                    await _api.quantity(sales[index].id, value);
                    if (mounted) setState(() => _sales = _api.sales());
                  },
                ),
          );
        },
      ),
    );
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _CreateHotSaleScreen(api: _api)),
    );
    if (saved == true && mounted) setState(() => _sales = _api.sales());
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({
    required this.sale,
    required this.language,
    required this.onChanged,
  });
  final _Sale sale;
  final String language;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final unit = _unitLabel(context, sale.unit);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC6D3C2)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.memory(
                  sale.image,
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sale.title(language),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      sale.description(language),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted),
                    ),
                    if (sale.isTranslated(language))
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed:
                            () => showDialog<void>(
                              context: context,
                              builder:
                                  (context) => AlertDialog(
                                    title: Text(
                                      localizeText(context, 'Original text'),
                                    ),
                                    content: Text(
                                      '${sale.originalTitle}\n\n${sale.originalDescription}',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text(
                                          localizeText(context, 'Close'),
                                        ),
                                      ),
                                    ],
                                  ),
                            ),
                        child: Text(
                          '${localizeText(context, 'AI translated from')} ${sale.originalLanguage.toUpperCase()} · ${localizeText(context, 'See original')}',
                        ),
                      ),
                    const SizedBox(height: 5),
                    Text(
                      '€${(sale.priceCents / 100).toStringAsFixed(2)} / $unit',
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {},
                child: Text(localizeText(context, 'Manage')),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Text(localizeText(context, 'Quantity'))),
              IconButton.filledTonal(
                onPressed:
                    sale.quantity > 0
                        ? () => onChanged(
                          (sale.quantity - 1).clamp(0, double.infinity),
                        )
                        : null,
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '${sale.quantity.toStringAsFixed(sale.quantity % 1 == 0 ? 0 : 1)} $unit',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => onChanged(sale.quantity + 1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreateHotSaleScreen extends StatefulWidget {
  const _CreateHotSaleScreen({required this.api});
  final _HotSalesApi api;
  @override
  State<_CreateHotSaleScreen> createState() => _CreateHotSaleScreenState();
}

class _CreateHotSaleScreenState extends State<_CreateHotSaleScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _production = TextEditingController();
  final _quantity = TextEditingController();
  final _price = TextEditingController();
  final _search = TextEditingController();
  String _originalLanguage = 'auto';
  String _unit = 'KILOGRAM';
  bool _farm = true;
  XFile? _photo;
  Uint8List? _photoBytes;
  bool _saving = false;
  late final Future<List<_Ring>> _rings = widget.api.rings();
  final Set<String> _ringIds = {};

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _production.dispose();
    _quantity.dispose();
    _price.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(localizeText(context, 'Add Hot Sale')),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
          children: [
            _section(
              context,
              'Product',
              'Choose what customers will see on your farm page.',
            ),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: localizeText(context, 'Product name'),
                hintText: localizeText(
                  context,
                  'For example: Fresh new potatoes',
                ),
                prefixIcon: const Icon(Icons.eco_outlined),
              ),
              validator:
                  (value) =>
                      (value?.trim().length ?? 0) < 2
                          ? localizeText(context, 'Enter a product name.')
                          : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _originalLanguage,
              decoration: InputDecoration(
                labelText: localizeText(context, 'Original language'),
                prefixIcon: const Icon(Icons.translate_rounded),
              ),
              items: [
                DropdownMenuItem(
                  value: 'auto',
                  child: Text(localizeText(context, 'Detect automatically')),
                ),
                const DropdownMenuItem(value: 'en', child: Text('English')),
                const DropdownMenuItem(value: 'fi', child: Text('Suomi')),
                const DropdownMenuItem(value: 'sv', child: Text('Svenska')),
              ],
              onChanged: (value) => setState(() => _originalLanguage = value!),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 7, 4, 0),
              child: Text(
                localizeText(
                  context,
                  'We keep your original and create searchable English, Finnish, and Swedish translations.',
                ),
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ),
            const SizedBox(height: 22),
            _section(
              context,
              'Stock and price',
              'Tell us how much is available and how you sell it.',
            ),
            DropdownButtonFormField<String>(
              value: _unit,
              decoration: InputDecoration(
                labelText: localizeText(context, 'How do you sell it?'),
                prefixIcon: const Icon(Icons.scale_outlined),
              ),
              items:
                  const [
                        'KILOGRAM',
                        'GRAM',
                        'LITRE',
                        'PIECE',
                        'BUNCH',
                        'BOX',
                        'DOZEN',
                      ]
                      .map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Text(_unitLabel(context, u)),
                        ),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _unit = value!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: localizeText(context, 'Available now'),
                prefixIcon: const Icon(Icons.inventory_2_outlined),
              ),
              validator: _positive,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: localizeText(context, 'Customer price'),
                prefixText: '€ ',
              ),
              validator: _positive,
            ),
            const SizedBox(height: 22),
            _section(
              context,
              'Product details',
              'A clear description helps customers decide.',
            ),
            TextFormField(
              controller: _description,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: localizeText(context, 'Description'),
              ),
              validator:
                  (value) =>
                      (value?.trim().length ?? 0) < 3
                          ? localizeText(context, 'Add a short description.')
                          : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _production,
              decoration: InputDecoration(
                labelText: localizeText(
                  context,
                  'Production details (optional)',
                ),
                prefixIcon: const Icon(Icons.info_outline),
              ),
            ),
            const SizedBox(height: 16),
            _photoPicker(),
            const SizedBox(height: 22),
            _section(
              context,
              'Available from',
              'Choose farm pickup, one or more REKO rings, or both.',
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(localizeText(context, 'At the farm')),
              subtitle: Text(
                localizeText(
                  context,
                  'Customers collect from your registered farm address.',
                ),
              ),
              value: _farm,
              onChanged: (value) => setState(() => _farm = value),
            ),
            FutureBuilder<List<_Ring>>(
              future: _rings,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done)
                  return const Padding(
                    padding: EdgeInsets.all(18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                if (snapshot.hasError)
                  return Text(
                    '${localizeText(context, 'Could not load REKO rings')}: ${snapshot.error}',
                  );
                final rings = snapshot.data ?? const [];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        labelText: localizeText(
                          context,
                          'Search REKO rings across Finland',
                        ),
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    if (_ringIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children:
                              rings
                                  .where((ring) => _ringIds.contains(ring.id))
                                  .map(
                                    (ring) => InputChip(
                                      avatar: const Icon(
                                        Icons.location_on_outlined,
                                        size: 17,
                                      ),
                                      label: Text(ring.name),
                                      onPressed: () => _showRing(ring),
                                      onDeleted:
                                          () => setState(
                                            () => _ringIds.remove(ring.id),
                                          ),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
                    if (rings.any((ring) => ring.priority < 2) &&
                        _search.text.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text(
                          localizeText(context, 'Suggested near you'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _green,
                          ),
                        ),
                      ),
                    ...rings
                        .where((ring) {
                          final q = _search.text.trim().toLowerCase();
                          return q.isEmpty ||
                              '${ring.name} ${ring.municipality} ${ring.region}'
                                  .toLowerCase()
                                  .contains(q);
                        })
                        .map(
                          (ring) => CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _ringIds.contains(ring.id),
                            onChanged:
                                (selected) => setState(
                                  () =>
                                      selected == true
                                          ? _ringIds.add(ring.id)
                                          : _ringIds.remove(ring.id),
                                ),
                            title: Row(
                              children: [
                                Expanded(child: Text(ring.name)),
                                if (ring.priority < 2)
                                  const Icon(
                                    Icons.near_me_outlined,
                                    size: 17,
                                    color: _green,
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              '${ring.municipality}${ring.region.isEmpty ? '' : ', ${ring.region}'}\n${ring.address}${ring.schedule.isEmpty ? '' : '\n${_scheduleLabel(context, ring.schedule)}'}',
                            ),
                            isThreeLine: true,
                          ),
                        ),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon:
                  _saving
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.add),
              label: Text(localizeText(context, 'Publish Hot Sale')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, String subtitle) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizeText(context, title),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              localizeText(context, subtitle),
              style: const TextStyle(color: _muted),
            ),
          ],
        ),
      );

  Widget _photoPicker() => InkWell(
    onTap: () async {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      if (mounted)
        setState(() {
          _photo = photo;
          _photoBytes = bytes;
        });
    },
    borderRadius: BorderRadius.circular(18),
    child: Container(
      height: 180,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFB9C8B5)),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child:
          _photoBytes == null
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_a_photo_outlined, color: _green),
                    const SizedBox(height: 8),
                    Text(localizeText(context, 'Add product photo')),
                  ],
                ),
              )
              : Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(_photoBytes!, fit: BoxFit.cover),
                  const Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.all(9),
                      child: CircleAvatar(child: Icon(Icons.edit_outlined)),
                    ),
                  ),
                ],
              ),
    ),
  );

  String? _positive(String? value) =>
      (double.tryParse((value ?? '').replaceAll(',', '.')) ?? 0) <= 0
          ? localizeText(context, 'Enter a value greater than zero.')
          : null;

  Future<void> _showRing(_Ring ring) => showDialog<void>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: Text(ring.name),
          content: Text(
            '${ring.address}\n${ring.municipality}'
            '${ring.region.isEmpty ? '' : ', ${ring.region}'}'
            '${ring.schedule.isEmpty ? '' : '\n\n${_scheduleLabel(context, ring.schedule)}'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(localizeText(context, 'Close')),
            ),
          ],
        ),
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_photoBytes == null || _photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizeText(context, 'Add one product photo.')),
        ),
      );
      return;
    }
    if (!_farm && _ringIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localizeText(
              context,
              'Choose farm pickup or at least one REKO ring.',
            ),
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final extension = _photo!.name.toLowerCase();
      final mime =
          extension.endsWith('.png')
              ? 'image/png'
              : extension.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';
      await widget.api.create({
        'originalLanguage': _originalLanguage,
        'originalTitle': _title.text.trim(),
        'description': _description.text.trim(),
        if (_production.text.trim().isNotEmpty)
          'productionDetail': _production.text.trim(),
        'unit': _unit,
        'priceCents':
            ((double.parse(_price.text.replaceAll(',', '.'))) * 100).round(),
        'quantity': double.parse(_quantity.text.replaceAll(',', '.')),
        'availableAtFarm': _farm,
        'rekoRingIds': _ringIds.toList(),
        'imageName': _photo!.name,
        'imageMimeType': mime,
        'imageBase64': base64Encode(_photoBytes!),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String _unitLabel(BuildContext context, String unit) =>
    localizeText(context, switch (unit) {
      'KILOGRAM' => 'kg',
      'GRAM' => 'g',
      'LITRE' => 'litre',
      'PIECE' => 'piece',
      'BUNCH' => 'bunch',
      'BOX' => 'box',
      'DOZEN' => 'dozen',
      _ => unit,
    });

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: _green),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
