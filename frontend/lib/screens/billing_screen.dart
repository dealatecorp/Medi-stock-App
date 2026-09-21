import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medistock_backend/medistock_backend.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../services/invoice_pdf_service.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  static const _paymentMethods = <String>[
    'Cash',
    'UPI',
    'Credit Card',
    'Credit',
  ];

  final _patient = TextEditingController();
  final _phone = TextEditingController();
  final _doctor = TextEditingController();
  final _upiId = TextEditingController();
  final _tax = TextEditingController(text: '0');
  final _discount = TextEditingController(text: '0');
  final _quantity = TextEditingController(text: '1');

  int? _selectedMedicineId;
  String _paymentMethod = 'Cash';
  DateTime? _nextRefillDate;
  InvoicePaperSize _paperSize = InvoicePaperSize.a4;
  bool _saving = false;

  double get _taxPercent => parsePercentage(_tax.text);
  double get _discountPercent => parsePercentage(_discount.text, maximum: 100);

  int get _grossPaise => widget.controller.cart.fold<int>(
    0,
    (sum, item) => sum + item.lineGrossPaise,
  );
  int get _lineDiscountPaise => widget.controller.cart.fold<int>(
    0,
    (sum, item) => sum + item.discountPaise,
  );
  int get _taxPaise => (_grossPaise * _taxPercent / 100).round();
  int get _discountPaise => (_grossPaise * _discountPercent / 100).round();
  int get _totalPaise =>
      (_grossPaise + _taxPaise - _lineDiscountPaise - _discountPaise)
          .clamp(0, 1 << 62)
          .toInt();

  String get _upiPaymentUri => Uri(
    scheme: 'upi',
    host: 'pay',
    queryParameters: <String, String>{
      'pa': _upiId.text.trim(),
      'pn': 'MediStock Pharmacy',
      'am': (_totalPaise / 100).toStringAsFixed(2),
      'cu': 'INR',
      'tn': 'MediStock invoice',
    },
  ).toString();

  @override
  void dispose() {
    _patient.dispose();
    _phone.dispose();
    _doctor.dispose();
    _upiId.dispose();
    _tax.dispose();
    _discount.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.controller.medicines;
    final availableIds = products.map((item) => item.id).toSet();
    if (!availableIds.contains(_selectedMedicineId)) {
      _selectedMedicineId = products.isEmpty ? null : products.first.id;
    }
    final selectedMedicine = products
        .where((medicine) => medicine.id == _selectedMedicineId)
        .firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 116),
      children: [
        SectionCard(
          title: 'Patient & prescription',
          trailing: widget.controller.invoices.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: _repeatPreviousSale,
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text('Repeat sale'),
                ),
          child: Column(
            children: [
              TextField(
                controller: _patient,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Patient name',
                  hintText: 'Walk-in patient',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  hintText: '9876543210',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _doctor,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Doctor (optional)',
                  hintText: 'Prescribing doctor',
                  prefixIcon: Icon(Icons.medical_information_outlined),
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final tax = TextField(
                    controller: _tax,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_percentageFormatter],
                    decoration: const InputDecoration(
                      labelText: 'Tax %',
                      prefixIcon: Icon(Icons.percent_rounded),
                    ),
                  );
                  final discount = TextField(
                    controller: _discount,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_percentageFormatter],
                    decoration: const InputDecoration(
                      labelText: 'Bill discount %',
                      prefixIcon: Icon(Icons.sell_outlined),
                    ),
                  );
                  return _responsivePair(
                    constraints: constraints,
                    first: tax,
                    second: discount,
                  );
                },
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final payment = DropdownButtonFormField<String>(
                    key: ValueKey(_paymentMethod),
                    initialValue: _paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    items: _paymentMethods
                        .map(
                          (method) => DropdownMenuItem(
                            value: method,
                            child: Text(method),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) =>
                        setState(() => _paymentMethod = value ?? 'Cash'),
                  );
                  final refill = InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _selectRefillDate,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Next refill (optional)',
                        prefixIcon: const Icon(Icons.event_repeat_outlined),
                        suffixIcon: _nextRefillDate == null
                            ? const Icon(Icons.calendar_today_outlined)
                            : IconButton(
                                tooltip: 'Clear refill date',
                                onPressed: () =>
                                    setState(() => _nextRefillDate = null),
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                      child: Text(
                        _nextRefillDate == null
                            ? 'Not scheduled'
                            : formatDate(_nextRefillDate),
                      ),
                    ),
                  );
                  return _responsivePair(
                    constraints: constraints,
                    first: payment,
                    second: refill,
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Add bill item',
          child: products.isEmpty
              ? const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No medicines available',
                  message: 'Add opening stock before creating a sale.',
                )
              : Column(
                  children: [
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Medicine and branch',
                        prefixIcon: Icon(Icons.medication_outlined),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: _selectedMedicineId,
                          items: products
                              .map(
                                (medicine) => DropdownMenuItem<int>(
                                  value: medicine.id,
                                  child: Text(
                                    '${medicine.name} - ${medicine.branch} '
                                    '(${medicine.stock > 0 ? '${medicine.stock} available' : 'out of stock'})',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) =>
                              setState(() => _selectedMedicineId = value),
                        ),
                      ),
                    ),
                    if (selectedMedicine != null) ...[
                      const SizedBox(height: 10),
                      _MedicineAvailabilityHint(medicine: selectedMedicine),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _quantity,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                              prefixIcon: Icon(Icons.numbers_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _addItem,
                          icon: const Icon(Icons.add_shopping_cart),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Bill items',
          trailing: widget.controller.cart.isEmpty
              ? null
              : TextButton(onPressed: _clearBill, child: const Text('Clear')),
          child: widget.controller.cart.isEmpty
              ? const EmptyState(
                  icon: Icons.shopping_cart_outlined,
                  title: 'No bill items',
                  message: 'Choose a medicine and quantity above.',
                )
              : Column(
                  children: [
                    for (var i = 0; i < widget.controller.cart.length; i++) ...[
                      _CartRow(
                        item: widget.controller.cart[i],
                        onDiscount: () =>
                            _editLineDiscount(widget.controller.cart[i]),
                        onRemove: () => widget.controller.removeFromCart(
                          widget.controller.cart[i].medicineId,
                        ),
                      ),
                      if (i < widget.controller.cart.length - 1)
                        const Divider(height: 20),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _TotalsCard(
          grossPaise: _grossPaise,
          lineDiscountPaise: _lineDiscountPaise,
          subtotalPaise: widget.controller.cartNetSubtotalPaise,
          taxPaise: _taxPaise,
          discountPaise: _discountPaise,
          totalPaise: _totalPaise,
        ),
        const SizedBox(height: 16),
        _buildOutputCard(),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final print = OutlinedButton.icon(
              onPressed: widget.controller.cart.isEmpty ? null : _printDraft,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print'),
            );
            final share = OutlinedButton.icon(
              onPressed: widget.controller.cart.isEmpty ? null : _shareDraft,
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share PDF'),
            );
            return _responsivePair(
              constraints: constraints,
              breakpoint: 390,
              first: print,
              second: share,
            );
          },
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: widget.controller.cart.isEmpty || _saving
              ? null
              : _saveInvoice,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.receipt_long_outlined),
          label: Text(_saving ? 'Saving invoice...' : 'Save & share invoice'),
        ),
      ],
    );
  }

  Widget _buildOutputCard() {
    final showUpi = _paymentMethod == 'UPI';
    final canRenderQr = showUpi && _isValidUpiId(_upiId.text);
    return SectionCard(
      title: 'Invoice output',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paper size',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final size in InvoicePaperSize.values)
                ChoiceChip(
                  selected: _paperSize == size,
                  onSelected: (_) => setState(() => _paperSize = size),
                  avatar: Icon(
                    size == InvoicePaperSize.thermal
                        ? Icons.receipt_outlined
                        : Icons.description_outlined,
                    size: 17,
                  ),
                  label: Text(size.label),
                ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: showUpi
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final field = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _upiId,
                              autocorrect: false,
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Pharmacy UPI ID',
                                hintText: 'medistock@bank',
                                prefixIcon: Icon(Icons.qr_code_2_rounded),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              canRenderQr
                                  ? 'The QR amount updates with this bill and is embedded in the PDF.'
                                  : 'Enter a valid UPI ID to create the local payment QR.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        );
                        final qr = AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: canRenderQr
                              ? Container(
                                  key: ValueKey(_upiPaymentUri),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: AppColors.forest.withValues(
                                        alpha: 0.18,
                                      ),
                                    ),
                                  ),
                                  child: QrImageView(
                                    data: _upiPaymentUri,
                                    size: 112,
                                    padding: EdgeInsets.zero,
                                    eyeStyle: const QrEyeStyle(
                                      color: AppColors.forestDark,
                                      eyeShape: QrEyeShape.square,
                                    ),
                                    dataModuleStyle: const QrDataModuleStyle(
                                      color: AppColors.ink,
                                      dataModuleShape: QrDataModuleShape.square,
                                    ),
                                  ),
                                )
                              : Container(
                                  key: const ValueKey('qr-placeholder'),
                                  width: 132,
                                  height: 132,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppColors.forestSoft,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.qr_code_2_rounded,
                                    color: AppColors.forest,
                                    size: 54,
                                  ),
                                ),
                        );
                        if (constraints.maxWidth < 480) {
                          return Column(
                            children: [field, const SizedBox(height: 14), qr],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: field),
                            const SizedBox(width: 18),
                            qr,
                          ],
                        );
                      },
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _selectRefillDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final suggested = _nextRefillDate ?? now.add(const Duration(days: 30));
    final initialDate = suggested.isBefore(today) ? today : suggested;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Schedule next refill',
    );
    if (picked != null && mounted) setState(() => _nextRefillDate = picked);
  }

  Future<void> _addItem() async {
    final id = _selectedMedicineId;
    final medicine = widget.controller.medicines
        .where((item) => item.id == id)
        .firstOrNull;
    if (medicine == null) {
      _message('Select a medicine.');
      return;
    }
    final parsed = int.tryParse(_quantity.text);
    if (parsed == null || parsed < 1) {
      _message('Enter a quantity of at least 1.');
      return;
    }
    final quantity = parsed.clamp(1, 1 << 31).toInt();
    try {
      widget.controller.addToCart(medicine, quantity);
      _quantity.text = '1';
    } catch (error) {
      final suggestions = widget.controller.substitutionSuggestions(
        medicine,
        quantity: quantity,
      );
      if (suggestions.isEmpty) {
        _message(
          '${_friendlyError(error)} No in-stock composition match found.',
        );
        return;
      }
      await _showSubstitutions(
        original: medicine,
        quantity: quantity,
        suggestions: suggestions,
      );
    }
  }

  Future<void> _showSubstitutions({
    required Medicine original,
    required int quantity,
    required List<Medicine> suggestions,
  }) async {
    final selected = await showModalBottomSheet<Medicine>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            0,
            18,
            18 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _RoundIcon(
                      icon: Icons.swap_horiz_rounded,
                      color: AppColors.gold,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose a substitute',
                            style: Theme.of(sheetContext).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            '${original.name} cannot fill $quantity unit${quantity == 1 ? '' : 's'}.',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (original.composition.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Same composition: ${original.composition.trim()}',
                    style: const TextStyle(
                      color: AppColors.forestDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: suggestions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final medicine = suggestions[index];
                      return Material(
                        color: AppColors.forestSoft.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(sheetContext, medicine),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        medicine.name,
                                        style: const TextStyle(
                                          color: AppColors.ink,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${medicine.branch} - ${medicine.stock} available - ${formatMoney(medicine.pricePaise)}',
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Icon(
                                  Icons.add_circle_rounded,
                                  color: AppColors.forest,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    try {
      widget.controller.addToCart(selected, quantity);
      _quantity.text = '1';
      setState(() => _selectedMedicineId = selected.id);
      _message('${selected.name} added as a composition substitute.');
    } catch (error) {
      _message(_friendlyError(error));
    }
  }

  Future<void> _repeatPreviousSale() async {
    final invoice = await showModalBottomSheet<InvoiceRecord>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final invoices = widget.controller.invoices.take(20).toList();
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _RoundIcon(
                        icon: Icons.history_rounded,
                        color: AppColors.forest,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Repeat a previous sale',
                              style: Theme.of(sheetContext).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const Text(
                              'Current stock is checked before items are added.',
                              style: TextStyle(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: invoices.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = invoices[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          title: Text(
                            item.customerName.trim().isEmpty
                                ? 'Walk-in patient'
                                : item.customerName,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${item.number} - ${formatDate(item.createdAt)} - ${item.totalQuantity} items',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatMoney(item.totalPaise),
                                style: const TextStyle(
                                  color: AppColors.forestDark,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                                color: AppColors.muted,
                              ),
                            ],
                          ),
                          onTap: () => Navigator.pop(sheetContext, item),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (invoice == null || !mounted) return;
    try {
      widget.controller.repeatInvoice(invoice);
      _patient.text = invoice.customerName == 'Walk-in patient'
          ? ''
          : invoice.customerName;
      _phone.text = invoice.customerPhone;
      _doctor.text = invoice.doctorName;
      _tax.text = _percentFrom(invoice.taxPaise, invoice.subtotalPaise);
      final priorLineDiscount = invoice.items.fold<int>(
        0,
        (sum, item) =>
            sum +
            (item.quantity * item.unitPricePaise * item.discountPercent / 100)
                .round(),
      );
      _discount.text = _percentFrom(
        (invoice.discountPaise - priorLineDiscount).clamp(0, 1 << 62),
        invoice.subtotalPaise,
      );
      setState(() {
        _paymentMethod = _paymentMethods.contains(invoice.paymentMethod)
            ? invoice.paymentMethod
            : 'Cash';
        _nextRefillDate = invoice.nextRefillDate;
      });
      _message('Previous sale loaded. Review stock and patient details.');
    } catch (error) {
      _message(_friendlyError(error));
    }
  }

  Future<void> _editLineDiscount(CartItem item) async {
    var value = item.discountPercent.clamp(0, 100).toDouble();
    final input = TextEditingController(text: _displayPercent(value));
    final result = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          18 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Line discount',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                item.medicineName,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: input,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_percentageFormatter],
                decoration: const InputDecoration(
                  labelText: 'Discount %',
                  prefixIcon: Icon(Icons.percent_rounded),
                ),
                onChanged: (text) {
                  final parsed = double.tryParse(text);
                  if (parsed == null) return;
                  setSheetState(() => value = parsed.clamp(0, 100));
                },
              ),
              Slider(
                value: value,
                min: 0,
                max: 100,
                divisions: 100,
                label: '${_displayPercent(value)}%',
                onChanged: (next) {
                  setSheetState(() => value = next);
                  input.text = _displayPercent(next);
                  input.selection = TextSelection.collapsed(
                    offset: input.text.length,
                  );
                },
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext, 0),
                    child: const Text('Remove discount'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, value),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    input.dispose();
    if (result == null || !mounted) return;
    widget.controller.updateCartItemDiscount(item.medicineId, result);
  }

  void _clearBill() {
    widget.controller.clearCart();
    _patient.clear();
    _phone.clear();
    _doctor.clear();
    _tax.text = '0';
    _discount.text = '0';
    setState(() {
      _paymentMethod = 'Cash';
      _nextRefillDate = null;
    });
  }

  InvoiceRecord _draft() => widget.controller.buildDraftInvoice(
    customerName: _patient.text,
    customerPhone: _phone.text,
    doctorName: _doctor.text,
    paymentMethod: _paymentMethod,
    nextRefillDate: _nextRefillDate,
    taxPercent: _taxPercent,
    discountPercent: _discountPercent,
  );

  Future<void> _printDraft() async {
    if (!_validatePayment()) return;
    try {
      await InvoicePdfService.printInvoice(
        _draft(),
        paperSize: _paperSize,
        upiId: _paymentMethod == 'UPI' ? _upiId.text.trim() : '',
      );
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
    }
  }

  Future<void> _shareDraft() async {
    if (_phone.text.trim().isEmpty) {
      _message('Enter the patient phone number first.');
      return;
    }
    if (!_validatePayment()) return;
    try {
      await InvoicePdfService.shareInvoice(
        _draft(),
        paperSize: _paperSize,
        upiId: _paymentMethod == 'UPI' ? _upiId.text.trim() : '',
      );
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
    }
  }

  Future<void> _saveInvoice() async {
    if (_phone.text.trim().isEmpty) {
      _message('Enter the patient phone number for the invoice.');
      return;
    }
    if (!_validatePayment()) return;
    setState(() => _saving = true);
    late final InvoiceRecord invoice;
    try {
      invoice = await widget.controller.createInvoice(
        customerName: _patient.text,
        customerPhone: _phone.text,
        doctorName: _doctor.text,
        paymentMethod: _paymentMethod,
        nextRefillDate: _nextRefillDate,
        taxPercent: _taxPercent,
        discountPercent: _discountPercent,
      );
      _patient.clear();
      _phone.clear();
      _doctor.clear();
      _tax.text = '0';
      _discount.text = '0';
      if (mounted) {
        setState(() {
          _paymentMethod = 'Cash';
          _nextRefillDate = null;
        });
        _message('Invoice ${invoice.number} saved. Opening share sheet...');
      }
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    try {
      await InvoicePdfService.shareInvoice(
        invoice,
        paperSize: _paperSize,
        upiId: invoice.paymentMethod == 'UPI' ? _upiId.text.trim() : '',
      );
    } catch (_) {
      if (mounted) {
        _message(
          'Invoice ${invoice.number} is saved, but the share sheet could not open. Retry from invoice history.',
        );
      }
    }
  }

  bool _validatePayment() {
    if (_paymentMethod != 'UPI') return true;
    if (_isValidUpiId(_upiId.text)) return true;
    _message('Enter a valid pharmacy UPI ID, for example medistock@bank.');
    return false;
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MedicineAvailabilityHint extends StatelessWidget {
  const _MedicineAvailabilityHint({required this.medicine});

  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    final available = medicine.stock > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: (available ? AppColors.success : AppColors.danger).withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            available ? Icons.check_circle_outline : Icons.info_outline,
            size: 17,
            color: available ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              available ? '${medicine.stock} units available now' : 'Out of stock. Add will suggest same-composition alternatives.',
              style: TextStyle(
                color: available ? AppColors.success : AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({
    required this.item,
    required this.onDiscount,
    required this.onRemove,
  });

  final CartItem item;
  final VoidCallback onDiscount;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.medicineName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                '${item.sku} - ${item.branch}\n'
                '${item.quantity} x ${formatMoney(item.unitPricePaise)}',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 6),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onDiscount,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item.discountPercent > 0
                        ? '${_displayPercent(item.discountPercent)}% line discount'
                        : 'Add line discount',
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (item.discountPaise > 0) ...[
              Text(
                formatMoney(item.lineGrossPaise),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              formatMoney(item.lineTotalPaise),
              style: const TextStyle(
                color: AppColors.forestDark,
                fontWeight: FontWeight.w900,
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              color: AppColors.danger,
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ],
        ),
      ],
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.grossPaise,
    required this.lineDiscountPaise,
    required this.subtotalPaise,
    required this.taxPaise,
    required this.discountPaise,
    required this.totalPaise,
  });

  final int grossPaise;
  final int lineDiscountPaise;
  final int subtotalPaise;
  final int taxPaise;
  final int discountPaise;
  final int totalPaise;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.forestDark, AppColors.forest],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -34,
              top: -45,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _row('Items total', grossPaise),
                  if (lineDiscountPaise > 0) ...[
                    const SizedBox(height: 8),
                    _row('Line discounts', -lineDiscountPaise),
                    const SizedBox(height: 8),
                    _row('After line discounts', subtotalPaise),
                  ],
                  const SizedBox(height: 8),
                  _row('Tax', taxPaise),
                  const SizedBox(height: 8),
                  _row('Bill discount', -discountPaise),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(color: Colors.white24),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        formatMoney(totalPaise),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, int value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: Colors.white70)),
      Text(
        formatMoney(value),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: color),
  );
}

Widget _responsivePair({
  required BoxConstraints constraints,
  required Widget first,
  required Widget second,
  double breakpoint = 520,
}) {
  if (constraints.maxWidth < breakpoint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [first, const SizedBox(height: 12), second],
    );
  }
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: first),
      const SizedBox(width: 12),
      Expanded(child: second),
    ],
  );
}

final _percentageFormatter = FilteringTextInputFormatter.allow(
  RegExp(r'^\d*\.?\d{0,2}'),
);

bool _isValidUpiId(String value) =>
    RegExp(r'^[A-Za-z0-9._-]{2,}@[A-Za-z0-9.-]{2,}$').hasMatch(value.trim());

String _percentFrom(int value, int base) {
  if (value <= 0 || base <= 0) return '0';
  return _displayPercent(value * 100 / base);
}

String _displayPercent(double value) =>
    value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

String _friendlyError(Object error) => error
    .toString()
    .replaceFirst('Exception: ', '')
    .replaceFirst('Bad state: ', '')
    .replaceFirst('Invalid argument(s): ', '');
