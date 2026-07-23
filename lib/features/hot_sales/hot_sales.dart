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
  String? get customUnit => json['customUnit'] as String?;
  String? get productionDetail => json['productionDetail'] as String?;
  bool get availableAtFarm => json['availableAtFarm'] as bool;
  String get status => json['status'] as String;
  String get imageName => json['imageName'] as String;
  String get imageMimeType => json['imageMimeType'] as String;
  List<String> get rekoRingIds =>
      (json['rekoRings'] as List<dynamic>)
          .map((ring) => (ring as Map<String, dynamic>)['id'] as String)
          .toList();
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
    const fields =
        'id categoryKey originalLanguage detectedLanguage originalTitle description productionDetail unit priceCents quantity producedAt availableAtFarm status imageName imageMimeType imageBase64 translations { locale title description productionDetail status provider model } rekoRings { id name municipality regionName }';
    Map<String, dynamic> data;
    try {
      data = await send('query { myHotSales { $fields customUnit } }');
    } on StateError catch (error) {
      if (!error.message.toString().contains('customUnit')) rethrow;
      // Keep the listing usable while a newly deployed API field is rolling out.
      data = await send('query { myHotSales { $fields } }');
    }
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
  Future<void> update(Map<String, dynamic> input) => send(
    'mutation(\$input: UpdateHotSaleInput!) { updateHotSale(input: \$input) { id } }',
    {'input': input},
  );
  Future<void> quantity(String id, double value) => send(
    'mutation(\$input: HotSaleQuantityInput!) { setHotSaleQuantity(input: \$input) { id } }',
    {
      'input': {'id': id, 'quantity': value},
    },
  );
  Future<void> availability(String id, bool available) => send(
    'mutation(\$input: HotSaleAvailabilityInput!) { setHotSaleAvailability(input: \$input) { id } }',
    {
      'input': {'id': id, 'available': available},
    },
  );
  Future<void> archive(String id) =>
      send('mutation(\$id: String!) { archiveHotSale(id: \$id) }', {'id': id});
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
                  onEdit: () => _edit(sales[index]),
                  onDelete: () => _delete(sales[index]),
                  onAvailabilityChanged: (available) async {
                    await _api.availability(sales[index].id, available);
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

  Future<void> _edit(_Sale sale) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _CreateHotSaleScreen(api: _api, sale: sale),
      ),
    );
    if (saved == true && mounted) setState(() => _sales = _api.sales());
  }

  Future<void> _delete(_Sale sale) async {
    final confirmed = await _confirmDelete(context, sale);
    if (!confirmed) return;
    await _api.archive(sale.id);
    if (mounted) setState(() => _sales = _api.sales());
  }
}

class HotSalesDashboardSection extends StatefulWidget {
  const HotSalesDashboardSection({super.key});

  @override
  State<HotSalesDashboardSection> createState() =>
      _HotSalesDashboardSectionState();
}

class _HotSalesDashboardSectionState extends State<HotSalesDashboardSection> {
  final _api = _HotSalesApi();
  late Future<List<_Sale>> _sales = _api.sales();

  void _reload() => setState(() => _sales = _api.sales());

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _CreateHotSaleScreen(api: _api)),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _edit(_Sale sale) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _CreateHotSaleScreen(api: _api, sale: sale),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _delete(_Sale sale) async {
    if (!await _confirmDelete(context, sale)) return;
    try {
      await _api.archive(sale.id);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _changeQuantity(_Sale sale, double value) async {
    try {
      await _api.quantity(sale.id, value);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _changeAvailability(_Sale sale, bool available) async {
    try {
      await _api.availability(sale.id, available);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                localizeText(context, 'Hot Sales'),
                style: const TextStyle(
                  color: _ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: Text(localizeText(context, 'Add product')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<_Sale>>(
          future: _sales,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return _InlineMessage(
                icon: Icons.cloud_off_outlined,
                text: localizeText(context, 'Could not load Hot Sales'),
                actionLabel: localizeText(context, 'Try again'),
                onAction: _reload,
              );
            }
            final sales = snapshot.data ?? const [];
            if (sales.isEmpty) {
              return _InlineMessage(
                icon: Icons.local_offer_outlined,
                text: localizeText(
                  context,
                  'No products yet. Add your first seasonal product.',
                ),
              );
            }
            return Column(
              children: [
                for (var index = 0; index < sales.length; index++) ...[
                  if (index > 0) const SizedBox(height: 12),
                  _SaleCard(
                    sale: sales[index],
                    language: language,
                    onChanged: (value) => _changeQuantity(sales[index], value),
                    onEdit: () => _edit(sales[index]),
                    onDelete: () => _delete(sales[index]),
                    onAvailabilityChanged:
                        (available) =>
                            _changeAvailability(sales[index], available),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({
    required this.sale,
    required this.language,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onAvailabilityChanged,
  });
  final _Sale sale;
  final String language;
  final ValueChanged<double> onChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onAvailabilityChanged;

  @override
  Widget build(BuildContext context) {
    final unit =
        sale.unit == 'OTHER' && sale.customUnit?.trim().isNotEmpty == true
            ? sale.customUnit!.trim()
            : _unitLabel(context, sale.unit);
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
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder:
                    (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(localizeText(context, 'Edit')),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          title: Text(
                            localizeText(context, 'Delete'),
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                sale.status == 'PAUSED'
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 19,
                color: sale.status == 'PAUSED' ? _muted : _green,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  localizeText(
                    context,
                    sale.status == 'PAUSED' ? 'Unavailable' : 'Available',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Switch.adaptive(
                value: sale.status != 'PAUSED',
                onChanged: onAvailabilityChanged,
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
  const _CreateHotSaleScreen({required this.api, this.sale});
  final _HotSalesApi api;
  final _Sale? sale;
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
  final _customUnit = TextEditingController();
  final _search = TextEditingController();
  String _unit = 'KILOGRAM';
  bool _farm = true;
  XFile? _photo;
  Uint8List? _photoBytes;
  bool _saving = false;
  late final Future<List<_Ring>> _rings = widget.api.rings();
  final Set<String> _ringIds = {};

  @override
  void initState() {
    super.initState();
    final sale = widget.sale;
    if (sale == null) return;
    _title.text = sale.originalTitle;
    _description.text = sale.originalDescription;
    _production.text = sale.productionDetail ?? '';
    _quantity.text = sale.quantity.toString();
    _price.text = (sale.priceCents / 100).toStringAsFixed(2);
    _unit = sale.unit;
    _customUnit.text = sale.customUnit ?? '';
    _farm = sale.availableAtFarm;
    _photoBytes = sale.image;
    _ringIds.addAll(sale.rekoRingIds);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _production.dispose();
    _quantity.dispose();
    _price.dispose();
    _customUnit.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(
          localizeText(
            context,
            widget.sale == null ? 'Add Hot Sale' : 'Edit Hot Sale',
          ),
        ),
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
                        'OTHER',
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
            if (_unit == 'OTHER') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _customUnit,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: localizeText(context, 'Custom selling unit'),
                  hintText: localizeText(
                    context,
                    'For example: bag, tray, jar, or 5 kg box',
                  ),
                  prefixIcon: const Icon(Icons.edit_outlined),
                ),
                onChanged: (_) => setState(() {}),
                validator:
                    (value) =>
                        (value?.trim().isEmpty ?? true)
                            ? localizeText(context, 'Enter your selling unit.')
                            : null,
              ),
            ],
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
                labelText:
                    '${localizeText(context, 'Customer price per')} '
                    '${_unit == 'OTHER' ? (_customUnit.text.trim().isEmpty ? localizeText(context, 'custom unit') : _customUnit.text.trim()) : _unitLabel(context, _unit)}',
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
              label: Text(
                localizeText(
                  context,
                  widget.sale == null ? 'Publish Hot Sale' : 'Save changes',
                ),
              ),
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
    if (_photoBytes == null) {
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
      final imageName = _photo?.name ?? widget.sale!.imageName;
      final extension = imageName.toLowerCase();
      final mime =
          _photo == null
              ? widget.sale!.imageMimeType
              : extension.endsWith('.png')
              ? 'image/png'
              : extension.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';
      final input = <String, dynamic>{
        if (widget.sale != null) 'id': widget.sale!.id,
        'originalLanguage':
            widget.sale?.originalLanguage ??
            Localizations.localeOf(context).languageCode,
        'originalTitle': _title.text.trim(),
        'description': _description.text.trim(),
        if (_production.text.trim().isNotEmpty)
          'productionDetail': _production.text.trim(),
        'unit': _unit,
        if (_unit == 'OTHER') 'customUnit': _customUnit.text.trim(),
        'priceCents':
            ((double.parse(_price.text.replaceAll(',', '.'))) * 100).round(),
        'quantity': double.parse(_quantity.text.replaceAll(',', '.')),
        'availableAtFarm': _farm,
        'rekoRingIds': _ringIds.toList(),
        'imageName': imageName,
        'imageMimeType': mime,
        'imageBase64': base64Encode(_photoBytes!),
      };
      if (widget.sale == null) {
        await widget.api.create(input);
      } else {
        await widget.api.update(input);
      }
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
      'OTHER' => 'Other / custom unit',
      _ => unit,
    });

Future<bool> _confirmDelete(BuildContext context, _Sale sale) async =>
    await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(localizeText(context, 'Delete product?')),
            content: Text(
              '${localizeText(context, 'This will remove')} '
              '"${sale.originalTitle}" '
              '${localizeText(context, 'from your Hot Sales list.')}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(localizeText(context, 'Cancel')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: Text(localizeText(context, 'Delete')),
              ),
            ],
          ),
    ) ??
    false;

void _showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
    );

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFD5DED1)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Icon(icon, color: _green),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(color: _muted))),
        if (onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel ?? 'Retry')),
      ],
    ),
  );
}

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
