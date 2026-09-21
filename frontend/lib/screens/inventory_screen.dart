import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medistock_backend/medistock_backend.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _ExpiryFilter _expiryFilter = _ExpiryFilter.all;
  String _scheduleFilter = 'All schedules';
  String _dosageFilter = 'All forms';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final now = DateTime.now();
    final medicines = widget.controller.medicines
        .where((medicine) {
          final matchesText =
              query.isEmpty ||
              <String>[
                medicine.name,
                medicine.sku,
                medicine.branch,
                medicine.brandName,
                medicine.genericName,
                medicine.scheduleCategory,
                medicine.dosageForm,
              ].join(' ').toLowerCase().contains(query);
          if (!matchesText) return false;

          final schedule = medicine.scheduleCategory.trim().isEmpty
              ? 'Unscheduled'
              : medicine.scheduleCategory;
          if (_scheduleFilter != 'All schedules' &&
              schedule != _scheduleFilter) {
            return false;
          }
          final dosage = medicine.dosageForm.trim().isEmpty
              ? 'Other'
              : medicine.dosageForm;
          if (_dosageFilter != 'All forms' && dosage != _dosageFilter) {
            return false;
          }

          final expiry = medicine.expiryDate;
          return switch (_expiryFilter) {
            _ExpiryFilter.all => true,
            _ExpiryFilter.expired => expiry != null && expiry.isBefore(now),
            _ExpiryFilter.threeMonths =>
              expiry != null &&
                  !expiry.isBefore(now) &&
                  expiry.isBefore(now.add(const Duration(days: 91))),
            _ExpiryFilter.sixMonths =>
              expiry != null &&
                  !expiry.isBefore(now) &&
                  expiry.isBefore(now.add(const Duration(days: 183))),
          };
        })
        .toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: widget.controller.staffBranch == null
                  ? 'Search medicine, batch, branch…'
                  : 'Search medicines in ${widget.controller.staffBranch}',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        _InventoryFilters(
          expiryFilter: _expiryFilter,
          scheduleFilter: _scheduleFilter,
          dosageFilter: _dosageFilter,
          onExpiryChanged: (value) => setState(() => _expiryFilter = value),
          onScheduleChanged: (value) => setState(() => _scheduleFilter = value),
          onDosageChanged: (value) => setState(() => _dosageFilter = value),
          onClear: () => setState(() {
            _expiryFilter = _ExpiryFilter.all;
            _scheduleFilter = 'All schedules';
            _dosageFilter = 'All forms';
          }),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: medicines.isEmpty
              ? EmptyState(
                  icon: Icons.medication_outlined,
                  title: _query.isEmpty
                      ? 'No medicines yet'
                      : 'No medicines found',
                  message: _query.isEmpty
                      ? 'Add stock manually, scan a barcode, or load sample data.'
                      : 'Try a different search or clear the stock filters.',
                  action: _query.isEmpty
                      ? FilledButton.icon(
                          onPressed: () =>
                              showMedicineFormSheet(context, widget.controller),
                          icon: const Icon(Icons.add),
                          label: const Text('Add medicine'),
                        )
                      : null,
                )
              : RefreshIndicator(
                  onRefresh: widget.controller.refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 116),
                    itemCount: medicines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final medicine = medicines[index];
                      return _MedicineCard(
                        medicine: medicine,
                        onAvailability: () =>
                            _showAvailability(context, medicine),
                        onEdit: () => showMedicineFormSheet(
                          context,
                          widget.controller,
                          medicine: medicine,
                        ),
                        onDelete: () => _deleteMedicine(context, medicine),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _deleteMedicine(BuildContext context, Medicine medicine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete medicine?'),
        content: Text(
          '${medicine.name} at ${medicine.branch} will be removed. Existing invoices stay intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || medicine.id == null || !context.mounted) return;
    try {
      await widget.controller.deleteMedicine(medicine.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Medicine deleted.')));
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _showAvailability(
    BuildContext context,
    Medicine medicine,
  ) async {
    final id = medicine.id;
    if (id == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      barrierColor: AppColors.ink.withValues(alpha: 0.46),
      sheetAnimationStyle: _sheetAnimationStyle(context),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: FutureBuilder<List<BranchAvailability>>(
            future: widget.controller.availabilityFor(id),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <BranchAvailability>[];
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medicine.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Batch / code: ${medicine.sku}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (snapshot.hasError)
                    Text('Unable to load availability: ${snapshot.error}')
                  else
                    ...rows.map(
                      (row) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: row.isCurrent
                                ? AppColors.forestSoft
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: row.isCurrent
                                  ? AppColors.forest.withValues(alpha: 0.3)
                                  : AppColors.muted.withValues(alpha: 0.18),
                            ),
                          ),
                          child: ListTile(
                            leading: Icon(
                              row.isCurrent
                                  ? Icons.store
                                  : Icons.store_outlined,
                              color: row.isCurrent
                                  ? AppColors.forest
                                  : AppColors.muted,
                            ),
                            title: Text(
                              row.branch,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(row.distanceLabel),
                            trailing: Text(
                              '${row.stock}',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: row.stock > 0
                                        ? AppColors.forestDark
                                        : AppColors.danger,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _ExpiryFilter { all, threeMonths, sixMonths, expired }

class _InventoryFilters extends StatelessWidget {
  const _InventoryFilters({
    required this.expiryFilter,
    required this.scheduleFilter,
    required this.dosageFilter,
    required this.onExpiryChanged,
    required this.onScheduleChanged,
    required this.onDosageChanged,
    required this.onClear,
  });

  final _ExpiryFilter expiryFilter;
  final String scheduleFilter;
  final String dosageFilter;
  final ValueChanged<_ExpiryFilter> onExpiryChanged;
  final ValueChanged<String> onScheduleChanged;
  final ValueChanged<String> onDosageChanged;
  final VoidCallback onClear;

  bool get _hasFilters =>
      expiryFilter != _ExpiryFilter.all ||
      scheduleFilter != 'All schedules' ||
      dosageFilter != 'All forms';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _FilterMenu<_ExpiryFilter>(
            icon: Icons.event_outlined,
            value: expiryFilter,
            label: switch (expiryFilter) {
              _ExpiryFilter.all => 'All expiry',
              _ExpiryFilter.threeMonths => '< 3 months',
              _ExpiryFilter.sixMonths => '< 6 months',
              _ExpiryFilter.expired => 'Expired',
            },
            options: const {
              _ExpiryFilter.all: 'All expiry',
              _ExpiryFilter.threeMonths: 'Expiring < 3 months',
              _ExpiryFilter.sixMonths: 'Expiring < 6 months',
              _ExpiryFilter.expired: 'Already expired',
            },
            onSelected: onExpiryChanged,
          ),
          const SizedBox(width: 8),
          _FilterMenu<String>(
            icon: Icons.policy_outlined,
            value: scheduleFilter,
            label: scheduleFilter,
            options: const {
              'All schedules': 'All schedules',
              'Unscheduled': 'Unscheduled',
              'Schedule H': 'Schedule H',
              'Schedule H1': 'Schedule H1',
            },
            onSelected: onScheduleChanged,
          ),
          const SizedBox(width: 8),
          _FilterMenu<String>(
            icon: Icons.category_outlined,
            value: dosageFilter,
            label: dosageFilter,
            options: const {
              'All forms': 'All forms',
              'Tablet': 'Tablet',
              'Capsule': 'Capsule',
              'Syrup': 'Syrup',
              'Injection': 'Injection',
              'Cream': 'Cream',
              'Drops': 'Drops',
              'Inhaler': 'Inhaler',
              'Other': 'Other',
            },
            onSelected: onDosageChanged,
          ),
          if (_hasFilters) ...[
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Clear'),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    required this.icon,
    required this.value,
    required this.label,
    required this.options,
    required this.onSelected,
  });

  final IconData icon;
  final T value;
  final String label;
  final Map<T, String> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => options.entries
          .map(
            (entry) => PopupMenuItem<T>(
              value: entry.key,
              child: Row(
                children: [
                  if (entry.key == value) ...[
                    const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: AppColors.forest,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(entry.value),
                ],
              ),
            ),
          )
          .toList(growable: false),
      child: Container(
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: value == options.keys.first
                ? AppColors.muted.withValues(alpha: 0.18)
                : AppColors.forest.withValues(alpha: 0.32),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: AppColors.forest),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicineCard extends StatelessWidget {
  const _MedicineCard({
    required this.medicine,
    required this.onAvailability,
    required this.onEdit,
    required this.onDelete,
  });

  final Medicine medicine;
  final VoidCallback onAvailability;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final meta = medicine.genericName.isNotEmpty
        ? medicine.genericName
        : medicine.brandName.isNotEmpty
        ? medicine.brandName
        : 'No generic or brand';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onAvailability,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          medicine.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$meta · ${medicine.sku}',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  StockBadge(
                    stock: medicine.stock,
                    threshold: medicine.reorderThreshold,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(icon: Icons.store_outlined, label: medicine.branch),
                  _InfoChip(
                    icon: Icons.shopping_cart_outlined,
                    label: 'Cost ${formatMoney(medicine.costPaise)}',
                  ),
                  _InfoChip(
                    icon: Icons.sell_outlined,
                    label: 'Price ${formatMoney(medicine.pricePaise)}',
                  ),
                  _InfoChip(
                    icon: Icons.category_outlined,
                    label: medicine.dosageForm.trim().isEmpty
                        ? 'Other'
                        : medicine.dosageForm,
                  ),
                  _InfoChip(
                    icon: Icons.policy_outlined,
                    label: medicine.scheduleCategory.trim().isEmpty
                        ? 'Unscheduled'
                        : medicine.scheduleCategory,
                  ),
                  if (medicine.expiryDate != null)
                    _InfoChip(
                      icon: Icons.event_outlined,
                      label: 'Exp ${formatDate(medicine.expiryDate!)}',
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onAvailability,
                    icon: const Icon(Icons.location_on_outlined, size: 19),
                    label: const Text('Branches'),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Edit',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    color: AppColors.danger,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.muted),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showMedicineFormSheet(
  BuildContext context,
  AppController controller, {
  Medicine? medicine,
}) async {
  final saved = await showModalBottomSheet<Medicine>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.canvas,
    barrierColor: AppColors.ink.withValues(alpha: 0.46),
    sheetAnimationStyle: _sheetAnimationStyle(context),
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.96,
      child: _MedicineForm(controller: controller, medicine: medicine),
    ),
  );
  if (saved != null && context.mounted) {
    final updatedExisting = medicine != null && saved.id == medicine.id;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updatedExisting ? 'Medicine updated.' : 'Medicine added.',
        ),
      ),
    );
  }
}

class _MedicineForm extends StatefulWidget {
  const _MedicineForm({required this.controller, this.medicine});

  final AppController controller;
  final Medicine? medicine;

  @override
  State<_MedicineForm> createState() => _MedicineFormState();
}

class _MedicineFormState extends State<_MedicineForm> {
  static const _scheduleOptions = <String>[
    'Unscheduled',
    'Schedule H',
    'Schedule H1',
  ];
  static const _dosageOptions = <String>[
    'Tablet',
    'Capsule',
    'Syrup',
    'Injection',
    'Cream',
    'Drops',
    'Inhaler',
    'Other',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _barcode;
  late final TextEditingController _name;
  late final TextEditingController _generic;
  late final TextEditingController _brand;
  late final TextEditingController _composition;
  late final TextEditingController _sku;
  late final TextEditingController _manufacturer;
  late final TextEditingController _stock;
  late final TextEditingController _threshold;
  late final TextEditingController _cost;
  late final TextEditingController _price;
  late String _branch;
  late String _scheduleCategory;
  late String _dosageForm;
  DateTime? _mfgDate;
  DateTime? _expiryDate;
  Medicine? _activeMedicine;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final value = widget.medicine;
    _activeMedicine = value;
    _barcode = TextEditingController(text: value?.barcode ?? '');
    _name = TextEditingController(text: value?.name ?? '');
    _generic = TextEditingController(text: value?.genericName ?? '');
    _brand = TextEditingController(text: value?.brandName ?? '');
    _composition = TextEditingController(text: value?.composition ?? '');
    _sku = TextEditingController(text: value?.sku ?? '');
    _manufacturer = TextEditingController(text: value?.manufacturer ?? '');
    _stock = TextEditingController(text: value == null ? '' : '${value.stock}');
    _threshold = TextEditingController(
      text: '${value?.reorderThreshold ?? 10}',
    );
    _cost = TextEditingController(
      text: value == null ? '' : (value.costPaise / 100).toStringAsFixed(2),
    );
    _price = TextEditingController(
      text: value == null ? '' : (value.pricePaise / 100).toStringAsFixed(2),
    );
    _branch =
        widget.controller.staffBranch ??
        value?.branch ??
        medistockBranches.first;
    _scheduleCategory = value?.scheduleCategory.trim().isNotEmpty == true
        ? value!.scheduleCategory
        : _scheduleOptions.first;
    _dosageForm = value?.dosageForm.trim().isNotEmpty == true
        ? value!.dosageForm
        : _dosageOptions.last;
    _mfgDate = value?.mfgDate;
    _expiryDate = value?.expiryDate;
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _barcode,
      _name,
      _generic,
      _brand,
      _composition,
      _sku,
      _manufacturer,
      _stock,
      _threshold,
      _cost,
      _price,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          _activeMedicine == null ? 'Add medicine' : 'Update medicine',
        ),
        actions: [
          IconButton(
            tooltip: 'Close',
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            OutlinedButton.icon(
              onPressed: _saving ? null : _scanBarcode,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan barcode'),
            ),
            const SizedBox(height: 14),
            _textField(
              _barcode,
              'Barcode / GTIN',
              hint: 'Scan or enter barcode',
              keyboardType: TextInputType.number,
            ),
            _textField(
              _name,
              'Medicine name',
              hint: 'Paracetamol 500mg tablets',
              required: true,
            ),
            _textField(_generic, 'Generic name', hint: 'Paracetamol'),
            _textField(_brand, 'Brand name', hint: 'Dolo 650'),
            _textField(
              _composition,
              'Composition',
              hint: 'Paracetamol IP 500mg',
            ),
            _textField(_sku, 'Batch / code', hint: 'PCM500-A1', required: true),
            _textField(
              _manufacturer,
              'Manufacturer',
              hint: 'Manufacturer name',
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final schedule = _choiceField(
                  'Regulatory schedule',
                  _scheduleCategory,
                  _scheduleOptions,
                  Icons.policy_outlined,
                  (value) => setState(() => _scheduleCategory = value),
                );
                final dosage = _choiceField(
                  'Dosage form',
                  _dosageForm,
                  _dosageOptions,
                  Icons.category_outlined,
                  (value) => setState(() => _dosageForm = value),
                );
                if (constraints.maxWidth < 520) {
                  return Column(children: [schedule, dosage]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: schedule),
                    const SizedBox(width: 12),
                    Expanded(child: dosage),
                  ],
                );
              },
            ),
            _dateField(
              'Manufacturing date',
              _mfgDate,
              (value) => setState(() => _mfgDate = value),
            ),
            _dateField(
              'Expiry date',
              _expiryDate,
              (value) => setState(() => _expiryDate = value),
            ),
            if (widget.controller.staffBranch != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Assigned branch',
                  ),
                  child: Text(widget.controller.staffBranch!),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_branch),
                  initialValue: _branch,
                  decoration: const InputDecoration(labelText: 'Branch'),
                  items: medistockBranches
                      .map(
                        (branch) => DropdownMenuItem(
                          value: branch,
                          child: Text(branch),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(
                    () => _branch = value ?? medistockBranches.first,
                  ),
                ),
              ),
            _numberField(_stock, 'Quantity', integer: true, required: true),
            _numberField(
              _threshold,
              'Reorder alert',
              integer: true,
              required: true,
            ),
            _numberField(_cost, 'Purchase price', required: true),
            _numberField(_price, 'Selling price', required: true),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _resetForm,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving…' : 'Save medicine'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    String? hint,
    bool required = false,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                  ? '$label is required.'
                  : null
            : null,
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    bool integer = false,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: !integer),
        inputFormatters: [
          if (integer) FilteringTextInputFormatter.digitsOnly,
          if (!integer)
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
        ],
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          if (required && (value == null || value.trim().isEmpty)) {
            return '$label is required.';
          }
          final parsed = double.tryParse(value?.trim() ?? '');
          if (parsed == null || parsed < 0) {
            return 'Enter a valid non-negative number.';
          }
          return null;
        },
      ),
    );
  }

  Widget _dateField(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final selected = await showDatePicker(
            context: context,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            initialDate: value ?? DateTime.now(),
          );
          if (selected != null) onChanged(selected);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: value == null
                ? const Icon(Icons.calendar_today_outlined)
                : IconButton(
                    tooltip: 'Clear date',
                    onPressed: () => onChanged(null),
                    icon: const Icon(Icons.close),
                  ),
          ),
          child: Text(value == null ? 'Not set' : formatDate(value)),
        ),
      ),
    );
  }

  Widget _choiceField(
    String label,
    String value,
    List<String> options,
    IconData icon,
    ValueChanged<String> onChanged,
  ) {
    final choices = options.contains(value)
        ? options
        : <String>[value, ...options];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label:$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        items: choices
            .map(
              (choice) => DropdownMenuItem(
                value: choice,
                child: Text(choice, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(growable: false),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }

  Future<void> _scanBarcode() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (value == null || value.trim().isEmpty || !mounted) return;
    _barcode.text = value;
    final existing = await widget.controller.lookupBarcode(value);
    if (existing == null || !mounted) return;
    setState(() {
      _name.text = existing.name;
      _generic.text = existing.genericName;
      _brand.text = existing.brandName;
      _composition.text = existing.composition;
      _sku.text = existing.sku;
      _manufacturer.text = existing.manufacturer;
      _mfgDate = existing.mfgDate;
      _expiryDate = existing.expiryDate;
      _branch = widget.controller.staffBranch ?? existing.branch;
      _threshold.text = '${existing.reorderThreshold}';
      _cost.text = (existing.costPaise / 100).toStringAsFixed(2);
      _price.text = (existing.pricePaise / 100).toStringAsFixed(2);
      _stock.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved medicine details filled. Enter this branch quantity.',
          ),
        ),
      );
    }
  }

  void _resetForm() {
    FocusManager.instance.primaryFocus?.unfocus();
    for (final controller in <TextEditingController>[
      _barcode,
      _name,
      _generic,
      _brand,
      _composition,
      _sku,
      _manufacturer,
      _stock,
      _cost,
      _price,
    ]) {
      controller.clear();
    }
    _threshold.text = '10';
    setState(() {
      _activeMedicine = null;
      _branch = widget.controller.staffBranch ?? medistockBranches.first;
      _scheduleCategory = _scheduleOptions.first;
      _dosageForm = _dosageOptions.last;
      _mfgDate = null;
      _expiryDate = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final existing = _activeMedicine;
      final value = Medicine(
        id: existing?.id,
        barcode: _barcode.text.trim(),
        name: _name.text.trim(),
        genericName: _generic.text.trim(),
        brandName: _brand.text.trim(),
        composition: _composition.text.trim(),
        sku: _sku.text.trim(),
        manufacturer: _manufacturer.text.trim(),
        scheduleCategory: _scheduleCategory,
        dosageForm: _dosageForm,
        mfgDate: _mfgDate,
        expiryDate: _expiryDate,
        branch: _branch,
        stock: int.parse(_stock.text),
        reorderThreshold: int.parse(_threshold.text),
        costPaise: parseMoneyToPaise(_cost.text),
        pricePaise: parseMoneyToPaise(_price.text),
        createdAt: existing?.createdAt,
        updatedAt: existing?.updatedAt,
      );
      final saved = await widget.controller.saveMedicine(value);
      if (mounted) Navigator.pop(context, saved);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final _manual = TextEditingController();
  late final MobileScannerController _scanner;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _scanner = MobileScannerController(
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.itf14,
      ],
    );
  }

  @override
  void dispose() {
    _manual.dispose();
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan medicine barcode'),
        actions: [
          IconButton(
            tooltip: 'Toggle torch',
            onPressed: _scanner.toggleTorch,
            icon: const Icon(Icons.flash_on_outlined),
          ),
          IconButton(
            tooltip: 'Switch camera',
            onPressed: _scanner.switchCamera,
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _scanner, onDetect: _onDetect),
                Center(
                  child: Container(
                    width: 290,
                    height: 170,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                const Positioned(
                  left: 24,
                  right: 24,
                  bottom: 24,
                  child: Text(
                    'Point the camera at an EAN, UPC, Code 39/128, or ITF barcode.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ColoredBox(
            color: AppColors.canvas,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manual,
                        keyboardType: TextInputType.number,
                        onSubmitted: (_) => _useManual(),
                        decoration: const InputDecoration(
                          hintText: 'Or type barcode number',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _useManual,
                      child: const Text('Use code'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null || raw.trim().isEmpty) return;
    _handled = true;
    await _scanner.stop();
    if (mounted) Navigator.pop(context, raw.trim());
  }

  void _useManual() {
    final value = _manual.text.replaceAll(RegExp(r'\D'), '');
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid barcode number.')),
      );
      return;
    }
    Navigator.pop(context, value);
  }
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
  );
}

AnimationStyle _sheetAnimationStyle(BuildContext context) {
  final reducedMotion = MediaQuery.disableAnimationsOf(context);
  return AnimationStyle(
    duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 260),
    reverseDuration: reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 180),
  );
}
