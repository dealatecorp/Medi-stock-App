import 'dart:async';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:medistock_backend/medistock_backend.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../services/purchase_invoice_reader.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _status = 'all';

  List<PurchaseRecord> get _filteredPurchases {
    final query = _query.trim().toLowerCase();
    return widget.controller.purchases
        .where((purchase) {
          if (_status != 'all' && purchase.status != _status) return false;
          if (query.isEmpty) return true;
          return <String>[
            purchase.invoiceNumber,
            purchase.supplierName,
            purchase.branch,
            for (final line in purchase.lines) ...[
              line.productName,
              line.batchNumber,
            ],
          ].join(' ').toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final purchases = _filteredPurchases;
    final allPurchases = widget.controller.purchases;

    return RefreshIndicator(
      onRefresh: widget.controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 116),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PageHeading(onAdd: () => _openEditor()),
                  const SizedBox(height: 18),
                  _PurchaseHero(purchases: allPurchases),
                  const SizedBox(height: 16),
                  _OfflineNote(),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      labelText: 'Search purchases',
                      hintText: 'Invoice, supplier, medicine, or batch',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'all',
                          label: Text('All'),
                          icon: Icon(Icons.view_agenda_outlined),
                        ),
                        ButtonSegment(
                          value: 'draft',
                          label: Text('Drafts'),
                          icon: Icon(Icons.edit_note_rounded),
                        ),
                        ButtonSegment(
                          value: 'completed',
                          label: Text('Completed'),
                          icon: Icon(Icons.task_alt_rounded),
                        ),
                      ],
                      selected: {_status},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        setState(() => _status = selection.first);
                      },
                    ),
                  ),
                  if (widget.controller.busy && allPurchases.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: const LinearProgressIndicator(minHeight: 3),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (widget.controller.busy && allPurchases.isEmpty)
                    const _LoadingPurchases()
                  else if (purchases.isEmpty)
                    SectionCard(
                      child: EmptyState(
                        icon: allPurchases.isEmpty
                            ? Icons.local_shipping_outlined
                            : Icons.manage_search_rounded,
                        title: allPurchases.isEmpty
                            ? 'No purchases yet'
                            : 'No purchases found',
                        message: allPurchases.isEmpty
                            ? 'Create a draft, add lines manually, or import a supplier CSV.'
                            : 'Try another search or status filter.',
                        action: allPurchases.isEmpty
                            ? FilledButton.icon(
                                onPressed: () => _openEditor(),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add purchase'),
                              )
                            : null,
                      ),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
                      child: Text(
                        'Purchase history · ${purchases.length}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    for (var index = 0; index < purchases.length; index++) ...[
                      _PurchaseCard(
                        key: ValueKey(
                          purchases[index].id ?? purchases[index].invoiceNumber,
                        ),
                        purchase: purchases[index],
                        onOpen: () => _openEditor(purchases[index]),
                        onDelete: () => _confirmDelete(purchases[index]),
                      ),
                      if (index < purchases.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor([PurchaseRecord? purchase]) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _PurchaseEditor(controller: widget.controller, purchase: purchase),
    );
    if (changed == true && mounted) {
      _showMessage(purchase == null ? 'Purchase saved.' : 'Purchase updated.');
    }
  }

  Future<void> _confirmDelete(PurchaseRecord purchase) async {
    final id = purchase.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: AppColors.danger),
        title: const Text('Delete purchase?'),
        content: Text(
          purchase.status == 'completed'
              ? 'Completed purchase ${purchase.invoiceNumber} will be removed. Inventory already received by this purchase is not reversed.'
              : 'Draft ${purchase.invoiceNumber} and its ${purchase.lines.length} line items will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.deletePurchase(id);
      if (mounted) _showMessage('Purchase deleted.');
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error), error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error ? AppColors.danger : AppColors.ink,
          content: Text(message),
        ),
      );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.onAdd});

  final VoidCallback onAdd;

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
                'Inventory',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Receive supplier stock with guided local matching',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add purchase'),
        ),
      ],
    );
  }
}

class _PurchaseHero extends StatelessWidget {
  const _PurchaseHero({required this.purchases});

  final List<PurchaseRecord> purchases;

  @override
  Widget build(BuildContext context) {
    final drafts = purchases.where((item) => item.status == 'draft').length;
    final completed = purchases
        .where((item) => item.status == 'completed')
        .toList(growable: false);
    final spend = completed.fold<int>(
      0,
      (total, purchase) => total + purchase.totalPaise,
    );

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.forestDark, AppColors.forest],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.forest.withValues(alpha: 0.18),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -72,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Purchase desk',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          Text(
                            'Draft safely, verify mappings, then receive stock',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.72),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _HeroPill(
                      icon: Icons.receipt_long_outlined,
                      value: '${purchases.length}',
                      label: 'Purchases',
                    ),
                    _HeroPill(
                      icon: Icons.edit_note_rounded,
                      value: '$drafts',
                      label: 'Drafts',
                    ),
                    _HeroPill(
                      icon: Icons.payments_outlined,
                      value: formatMoney(spend),
                      label: 'Received value',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 116),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.82), size: 19),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.68)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.offline_bolt_outlined, color: AppColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Medicine matching uses this device\'s local catalog. No supplier file leaves the phone.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({
    super.key,
    required this.purchase,
    required this.onOpen,
    required this.onDelete,
  });

  final PurchaseRecord purchase;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final completed = purchase.status == 'completed';
    final color = completed ? AppColors.success : AppColors.warning;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    completed
                        ? Icons.task_alt_rounded
                        : Icons.edit_note_rounded,
                    color: color,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        purchase.supplierName.isEmpty
                            ? 'Supplier purchase'
                            : purchase.supplierName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        purchase.invoiceNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMoney(purchase.totalPaise),
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      completed ? 'COMPLETED' : 'DRAFT',
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${formatDate(purchase.invoiceDate)} · ${purchase.branch}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.muted),
            ),
            const Divider(height: 24),
            Row(
              children: [
                _CardFact(label: 'Items', value: '${purchase.lines.length}'),
                _CardFact(
                  label: 'Subtotal',
                  value: formatMoney(purchase.subtotalPaise),
                ),
                _CardFact(label: 'GST', value: formatMoney(purchase.gstPaise)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!completed) ...[
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: Icon(
                    completed
                        ? Icons.visibility_outlined
                        : Icons.arrow_forward_rounded,
                  ),
                  label: Text(completed ? 'View' : 'Continue'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardFact extends StatelessWidget {
  const _CardFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _PurchaseEditor extends StatefulWidget {
  const _PurchaseEditor({required this.controller, this.purchase});

  final AppController controller;
  final PurchaseRecord? purchase;

  @override
  State<_PurchaseEditor> createState() => _PurchaseEditorState();
}

class _PurchaseEditorState extends State<_PurchaseEditor> {
  final _invoiceController = TextEditingController();
  Timer? _autosaveTimer;
  PurchaseRecord? _savedPurchase;
  Supplier? _supplier;
  late DateTime _invoiceDate;
  late String _branch;
  late List<PurchaseLine> _lines;
  final Map<int, LastPurchaseInfo?> _purchaseHistory = {};
  bool _saving = false;
  bool _importing = false;
  bool _readingInvoice = false;
  bool _finalizing = false;
  bool _hasUnsavedChanges = false;
  bool _forceClose = false;
  bool _didSave = false;
  String _saveState = 'Changes are saved as a local draft';

  bool get _readOnly => widget.purchase?.status == 'completed';

  @override
  void initState() {
    super.initState();
    _savedPurchase = widget.purchase;
    _invoiceController.text = widget.purchase?.invoiceNumber ?? '';
    _invoiceDate = widget.purchase?.invoiceDate ?? DateTime.now();
    _branch =
        widget.controller.currentStaff?.branch ??
        widget.purchase?.branch ??
        medistockBranches.first;
    _lines = [...?widget.purchase?.lines];
    final supplierId = widget.purchase?.supplierId;
    if (supplierId != null) {
      for (final candidate in widget.controller.suppliers) {
        if (candidate.id == supplierId) {
          _supplier = candidate;
          break;
        }
      }
    }
    for (final line in _lines) {
      _loadPurchaseHistory(line.medicineId);
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _invoiceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      canPop: _forceClose || (!_hasUnsavedChanges && !_saving && !_finalizing),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeEditor();
      },
      child: Material(
        color: AppColors.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height,
          child: Column(
            children: [
              _EditorHeader(
                readOnly: _readOnly,
                saving: _saving,
                saveState: _saveState,
                onClose: _closeEditor,
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 20 + keyboard),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 850),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _StepLabel(
                              number: '01',
                              title: 'Purchase details',
                              subtitle: 'Link the supplier and invoice',
                            ),
                            const SizedBox(height: 10),
                            SectionCard(child: _buildHeaderForm()),
                            const SizedBox(height: 20),
                            _StepLabel(
                              number: '02',
                              title: 'Add stock lines',
                              subtitle:
                                  'Import a CSV or enter each batch manually',
                            ),
                            const SizedBox(height: 10),
                            _buildImportPanel(),
                            const SizedBox(height: 12),
                            if (_lines.isEmpty)
                              SectionCard(
                                child: EmptyState(
                                  icon: Icons.playlist_add_rounded,
                                  title: 'No purchase lines',
                                  message: 'Add a medicine manually or import your supplier invoice.',
                                  action: _readOnly
                                      ? null
                                      : FilledButton.icon(
                                          onPressed: _addLine,
                                          icon: const Icon(Icons.add_rounded),
                                          label: const Text('Add first item'),
                                        ),
                                ),
                              )
                            else
                              for (
                                var index = 0;
                                index < _lines.length;
                                index++
                              ) ...[
                                _PurchaseLineCard(
                                  line: _lines[index],
                                  history:
                                      _purchaseHistory[_lines[index]
                                          .medicineId],
                                  readOnly: _readOnly,
                                  onEdit: () => _editLine(index),
                                  onDelete: () {
                                    setState(() => _lines.removeAt(index));
                                    _materialChanged();
                                  },
                                ),
                                if (index < _lines.length - 1)
                                  const SizedBox(height: 10),
                              ],
                            if (_lines.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              _TotalsCard(lines: _lines),
                            ],
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_readOnly)
                _EditorFooter(
                  saving: _saving,
                  finalizing: _finalizing,
                  total: _draftTotal,
                  onSave: () => _persistDraft(showFeedback: true),
                  onFinalize: _finalize,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderForm() {
    final supplierItems = widget.controller.suppliers
        .where((supplier) => supplier.isActive || supplier.id == _supplier?.id)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _supplier?.id,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Supplier / distributor *',
                  prefixIcon: Icon(Icons.local_shipping_outlined),
                ),
                items: supplierItems
                    .where((supplier) => supplier.id != null)
                    .map(
                      (supplier) => DropdownMenuItem<int>(
                        value: supplier.id,
                        child: Text(
                          supplier.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _readOnly
                    ? null
                    : (id) {
                        setState(() {
                          _supplier = supplierItems
                              .where((item) => item.id == id)
                              .firstOrNull;
                        });
                        _materialChanged();
                      },
              ),
            ),
            if (!_readOnly) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Create supplier',
                constraints: const BoxConstraints.tightFor(
                  width: 52,
                  height: 52,
                ),
                onPressed: _createSupplier,
                icon: const Icon(Icons.person_add_alt_1_rounded),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final invoice = TextField(
              controller: _invoiceController,
              enabled: !_readOnly,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => _materialChanged(),
              decoration: const InputDecoration(
                labelText: 'Invoice number *',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
            );
            final date = _PickerField(
              label: 'Invoice date *',
              value: formatDate(_invoiceDate),
              icon: Icons.calendar_month_outlined,
              enabled: !_readOnly,
              onTap: _pickInvoiceDate,
            );
            if (compact) {
              return Column(
                children: [invoice, const SizedBox(height: 12), date],
              );
            }
            return Row(
              children: [
                Expanded(child: invoice),
                const SizedBox(width: 12),
                Expanded(child: date),
              ],
            );
          },
        ),
        if (!_readOnly) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _readingInvoice ? null : _uploadInvoice,
              icon: _readingInvoice
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(
                _readingInvoice
                    ? 'Reading invoice…'
                    : 'Read number from PDF/photo',
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Review the detected number before saving. The file is not attached.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (widget.controller.currentStaff != null)
          TextFormField(
            initialValue: _branch,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Receiving branch',
              helperText: 'Assigned automatically from your staff profile',
              prefixIcon: Icon(Icons.storefront_outlined),
              suffixIcon: Icon(Icons.lock_outline_rounded),
            ),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _branch,
            decoration: const InputDecoration(
              labelText: 'Receiving branch *',
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
            items: medistockBranches
                .map(
                  (branch) =>
                      DropdownMenuItem(value: branch, child: Text(branch)),
                )
                .toList(growable: false),
            onChanged: _readOnly
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _branch = value);
                    _materialChanged();
                  },
          ),
      ],
    );
  }

  Widget _buildImportPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.forest.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.forestSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.table_view_outlined,
                  color: AppColors.forest,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Supplier CSV',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Headers tolerate spaces, underscores, and letter case',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            'Product Name • Batch Number • Expiry Date • Billed Quantity • Free Quantity • MRP • Purchase Rate • GST Percentage',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppColors.muted, height: 1.45),
          ),
          if (!_readOnly) ...[
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 9,
              runSpacing: 9,
              children: [
                OutlinedButton.icon(
                  onPressed: _importing ? null : _importCsv,
                  icon: _importing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined),
                  label: Text(_importing ? 'Reading file…' : 'Import CSV'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _addLine,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add manually'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  int get _draftTotal {
    var subtotal = 0;
    var gst = 0;
    for (final line in _lines) {
      final base = line.billedQuantity * line.purchaseRatePaise;
      subtotal += base;
      gst += (base * line.gstPercent / 100).round();
    }
    return subtotal + gst;
  }

  Future<void> _closeEditor() async {
    if (_forceClose || _saving || _finalizing) return;
    if (_hasUnsavedChanges && _canPersist) {
      final saved = await _persistDraft();
      if (!saved || !mounted) return;
    } else if (_hasUnsavedChanges && !_canPersist) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.edit_note_rounded, color: AppColors.warning),
          title: const Text('Discard incomplete draft?'),
          content: const Text(
            'Choose a supplier and enter an invoice number to save this draft.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
      setState(() => _hasUnsavedChanges = false);
    }
    if (!mounted) return;
    setState(() => _forceClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, _didSave);
    });
  }

  void _materialChanged() {
    if (_readOnly) return;
    setState(() {
      _hasUnsavedChanges = true;
      _saveState = 'Unsaved local changes';
    });
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted && _canPersist) _persistDraft();
    });
  }

  bool get _canPersist =>
      _supplier?.id != null && _invoiceController.text.trim().isNotEmpty;

  PurchaseRecord _buildRecord() {
    return PurchaseRecord(
      id: _savedPurchase?.id,
      supplierId: _supplier!.id!,
      supplierName: _supplier!.name,
      invoiceNumber: _invoiceController.text.trim(),
      invoiceDate: _invoiceDate,
      branch: _branch,
      status: 'draft',
      lines: List<PurchaseLine>.unmodifiable(_lines),
      createdAt: _savedPurchase?.createdAt,
      updatedAt: _savedPurchase?.updatedAt,
    );
  }

  Future<bool> _persistDraft({bool showFeedback = false}) async {
    _autosaveTimer?.cancel();
    if (!_canPersist) {
      if (showFeedback) {
        _showMessage('Choose a supplier and enter an invoice number.');
      }
      return false;
    }
    if (_saving) return false;
    setState(() {
      _saving = true;
      _saveState = 'Saving draft…';
    });
    try {
      final saved = await widget.controller.savePurchase(_buildRecord());
      if (!mounted) return true;
      setState(() {
        _savedPurchase = saved;
        _hasUnsavedChanges = false;
        _didSave = true;
        _saveState = 'Draft saved on this device';
      });
      if (showFeedback) _showMessage('Draft saved locally.');
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _saveState = 'Could not save draft');
      _showMessage(_friendlyError(error), error: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finalize() async {
    _autosaveTimer?.cancel();
    final issue = _validationIssue;
    if (issue != null) {
      _showMessage(issue, error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.inventory_2_outlined, color: AppColors.forest),
        title: const Text('Receive this purchase?'),
        content: Text(
          '${_lines.length} batch lines worth ${formatMoney(_draftTotal)} will be added to $_branch. This finalizes the draft.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Review'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.task_alt_rounded),
            label: const Text('Receive stock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _finalizing = true);
    try {
      if (_hasUnsavedChanges || _savedPurchase?.id == null) {
        final saved = await _persistDraft();
        if (!saved) return;
      }
      await widget.controller.completePurchase(_savedPurchase!.id!);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _finalizing = false);
    }
  }

  String? get _validationIssue {
    if (_supplier?.id == null) return 'Choose a supplier before finalizing.';
    if (_invoiceController.text.trim().isEmpty) {
      return 'Enter the supplier invoice number.';
    }
    if (_lines.isEmpty) return 'Add at least one purchase line.';
    if (_lines.any((line) => line.medicineId == null)) {
      return 'Resolve every unmatched medicine before finalizing.';
    }
    if (_lines.any((line) => line.batchNumber.trim().isEmpty)) {
      return 'Every line needs a batch number.';
    }
    if (_lines.any((line) => line.billedQuantity + line.freeQuantity <= 0)) {
      return 'Every line needs a billed or free quantity.';
    }
    return null;
  }

  Future<void> _pickInvoiceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() => _invoiceDate = picked);
    _materialChanged();
  }

  Future<void> _createSupplier() async {
    final supplier = await showModalBottomSheet<Supplier>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SupplierEditor(controller: widget.controller),
    );
    if (supplier == null || !mounted) return;
    setState(() => _supplier = supplier);
    _materialChanged();
  }

  Future<void> _addLine() async {
    final line = await showModalBottomSheet<PurchaseLine>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _LineEditor(controller: widget.controller, branch: _branch),
    );
    if (line == null || !mounted) return;
    setState(() => _lines.add(line));
    _loadPurchaseHistory(line.medicineId);
    _materialChanged();
  }

  Future<void> _editLine(int index) async {
    final line = await showModalBottomSheet<PurchaseLine>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LineEditor(
        controller: widget.controller,
        branch: _branch,
        line: _lines[index],
      ),
    );
    if (line == null || !mounted) return;
    setState(() => _lines[index] = line);
    _loadPurchaseHistory(line.medicineId);
    _materialChanged();
  }

  Future<void> _loadPurchaseHistory(int? medicineId) async {
    if (medicineId == null || _purchaseHistory.containsKey(medicineId)) return;
    _purchaseHistory[medicineId] = null;
    try {
      final info = await widget.controller.getLastPurchaseInfo(medicineId);
      if (!mounted) return;
      setState(() => _purchaseHistory[medicineId] = info);
    } catch (_) {
      // Historical guidance is optional and should never block a purchase.
    }
  }

  Future<void> _uploadInvoice() async {
    setState(() => _readingInvoice = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (file == null) return;
      final path = file.path;
      if (path == null) {
        throw StateError('The selected invoice could not be opened.');
      }
      final number = await PurchaseInvoiceReader().extractInvoiceNumber(path);
      if (!mounted) return;
      if (number == null || number.trim().isEmpty) {
        _showMessage(
          'No clear invoice number was found. Enter it manually.',
          error: true,
        );
        return;
      }
      setState(() => _invoiceController.text = number.trim());
      _materialChanged();
      _showMessage('Invoice number detected. Please verify it before saving.');
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Could not read the invoice: ${_friendlyError(error)} Enter the number manually.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _readingInvoice = false);
    }
  }

  Future<void> _importCsv() async {
    setState(() => _importing = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final contents = utf8.decode(bytes, allowMalformed: true);
      final decoded = csv.decode(contents);
      if (decoded.length < 2) {
        throw const FormatException('The CSV has no purchase rows.');
      }
      final headers = decoded.first
          .map((value) => _normaliseHeader(value.toString()))
          .toList(growable: false);
      final productIndex = headers.indexOf('productname');
      if (productIndex < 0) {
        throw const FormatException('The CSV needs a Product_Name column.');
      }
      int indexOf(String name) => headers.indexOf(name);
      String cell(List<dynamic> row, int index) =>
          index < 0 || index >= row.length ? '' : row[index].toString().trim();

      final imported = <PurchaseLine>[];
      for (final row in decoded.skip(1)) {
        final productName = cell(row, productIndex);
        if (productName.isEmpty) continue;
        final candidates = await widget.controller.findMedicineCandidates(
          productName,
        );
        MedicineMatch? match;
        if (candidates.isNotEmpty) match = candidates.first;
        final exact =
            match != null &&
            match.medicine.name.trim().toLowerCase() ==
                productName.toLowerCase();
        final usablePartial = match != null && match.score >= 0.45;
        final expiry = _parseCsvDate(cell(row, indexOf('expirydate')));
        imported.add(
          PurchaseLine(
            medicineId: exact || usablePartial ? match.medicine.id : null,
            productName: productName,
            batchNumber: cell(row, indexOf('batchnumber')),
            expiryDate: expiry,
            billedQuantity: _parseWhole(cell(row, indexOf('billedquantity'))),
            freeQuantity: _parseWhole(cell(row, indexOf('freequantity'))),
            mrpPaise: _parseCsvMoney(cell(row, indexOf('mrp'))),
            purchaseRatePaise: _parseCsvMoney(
              cell(row, indexOf('purchaserate')),
            ),
            gstPercent: _parseNumber(cell(row, indexOf('gstpercentage'))),
            matchState: exact
                ? 'exact'
                : usablePartial
                ? 'partial'
                : 'unmatched',
            matchScore: match?.score ?? 0,
          ),
        );
      }
      if (imported.isEmpty) {
        throw const FormatException('No valid product rows were found.');
      }
      if (!mounted) return;
      setState(() => _lines.addAll(imported));
      for (final line in imported) {
        _loadPurchaseHistory(line.medicineId);
      }
      _materialChanged();
      final unresolved = imported
          .where((line) => line.medicineId == null)
          .length;
      _showMessage(
        'Imported ${imported.length} lines${unresolved == 0 ? '' : ' • $unresolved need matching'}.',
      );
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error ? AppColors.danger : AppColors.ink,
          content: Text(message),
        ),
      );
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.readOnly,
    required this.saving,
    required this.saveState,
    required this.onClose,
  });

  final bool readOnly;
  final bool saving;
  final String saveState;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.muted.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close purchase',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  readOnly ? 'Purchase details' : 'Purchase draft',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Row(
                  children: [
                    if (saving) ...[
                      const SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      ),
                      const SizedBox(width: 6),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.offline_bolt_outlined,
                          size: 14,
                          color: AppColors.forest,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        readOnly ? 'Completed stock receipt' : saveState,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  final String number;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.forest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PurchaseLineCard extends StatelessWidget {
  const _PurchaseLineCard({
    required this.line,
    required this.history,
    required this.readOnly,
    required this.onEdit,
    required this.onDelete,
  });

  final PurchaseLine line;
  final LastPurchaseInfo? history;
  final bool readOnly;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final state = _matchVisual(line.matchState);
    final base = line.billedQuantity * line.purchaseRatePaise;
    final gst = (base * line.gstPercent / 100).round();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: state.color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: state.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(state.icon, color: state.color, size: 21),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 7,
                        runSpacing: 5,
                        children: [
                          _SmallBadge(text: state.label, color: state.color),
                          if (line.batchNumber.isNotEmpty)
                            _SmallBadge(
                              text: 'Batch ${line.batchNumber}',
                              color: AppColors.muted,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!readOnly)
                  PopupMenuButton<String>(
                    tooltip: 'Line actions',
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit line'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(
                            Icons.delete_outline,
                            color: AppColors.danger,
                          ),
                          title: Text('Remove line'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 13),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _LineFact(
                  label: 'Quantity',
                  value:
                      '${line.billedQuantity} billed + ${line.freeQuantity} free',
                ),
                _LineFact(
                  label: 'Purchase rate',
                  value: formatMoney(line.purchaseRatePaise),
                ),
                _LineFact(label: 'MRP', value: formatMoney(line.mrpPaise)),
                _LineFact(
                  label: 'GST',
                  value: '${_trimDecimal(line.gstPercent)}%',
                ),
                _LineFact(label: 'Line total', value: formatMoney(base + gst)),
              ],
            ),
            if (history != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.history_rounded,
                      color: AppColors.gold,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Last: ${formatMoney(history!.purchaseRatePaise)} from ${history!.supplierName} • ${formatDate(history!.invoiceDate)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _LineFact extends StatelessWidget {
  const _LineFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 105),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.lines});

  final List<PurchaseLine> lines;

  @override
  Widget build(BuildContext context) {
    final subtotal = lines.fold<int>(
      0,
      (sum, line) => sum + line.billedQuantity * line.purchaseRatePaise,
    );
    final gst = lines.fold<int>(0, (sum, line) {
      final base = line.billedQuantity * line.purchaseRatePaise;
      return sum + (base * line.gstPercent / 100).round();
    });
    final units = lines.fold<int>(
      0,
      (sum, line) => sum + line.billedQuantity + line.freeQuantity,
    );
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.forestSoft,
            AppColors.forestSoft.withValues(alpha: 0.34),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          _TotalRow(label: '$units total units', value: formatMoney(subtotal)),
          const SizedBox(height: 8),
          _TotalRow(label: 'GST', value: formatMoney(gst)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 9),
            child: Divider(height: 1),
          ),
          _TotalRow(
            label: 'Purchase total',
            value: formatMoney(subtotal + gst),
            prominent: true,
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.prominent = false,
  });

  final String label;
  final String value;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final style = prominent
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: style?.copyWith(
              color: prominent ? AppColors.ink : AppColors.muted,
              fontWeight: prominent ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: style?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _EditorFooter extends StatelessWidget {
  const _EditorFooter({
    required this.saving,
    required this.finalizing,
    required this.total,
    required this.onSave,
    required this.onFinalize,
  });

  final bool saving;
  final bool finalizing;
  final int total;
  final VoidCallback onSave;
  final VoidCallback onFinalize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.muted.withValues(alpha: 0.12)),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  formatMoney(total),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: saving || finalizing ? null : onSave,
            child: Text(saving ? 'Saving…' : 'Save draft'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: saving || finalizing ? null : onFinalize,
            child: finalizing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Receive'),
          ),
        ],
      ),
    );
  }
}

class _LineEditor extends StatefulWidget {
  const _LineEditor({
    required this.controller,
    required this.branch,
    this.line,
  });

  final AppController controller;
  final String branch;
  final PurchaseLine? line;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _product;
  late final TextEditingController _batch;
  late final TextEditingController _billed;
  late final TextEditingController _free;
  late final TextEditingController _mrp;
  late final TextEditingController _rate;
  late final TextEditingController _gst;
  DateTime? _expiry;
  List<MedicineMatch> _candidates = const [];
  Medicine? _selectedMedicine;
  LastPurchaseInfo? _history;
  String _matchState = 'unmatched';
  double _matchScore = 0;
  bool _searching = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    final line = widget.line;
    _product = TextEditingController(text: line?.productName ?? '');
    _batch = TextEditingController(text: line?.batchNumber ?? '');
    _billed = TextEditingController(
      text: line == null ? '1' : '${line.billedQuantity}',
    );
    _free = TextEditingController(
      text: line == null ? '0' : '${line.freeQuantity}',
    );
    _mrp = TextEditingController(
      text: line == null ? '' : _moneyInput(line.mrpPaise),
    );
    _rate = TextEditingController(
      text: line == null ? '' : _moneyInput(line.purchaseRatePaise),
    );
    _gst = TextEditingController(
      text: line == null ? '0' : _trimDecimal(line.gstPercent),
    );
    _expiry = line?.expiryDate;
    _matchState = line?.matchState ?? 'unmatched';
    _matchScore = line?.matchScore ?? 0;
    final medicineId = line?.medicineId;
    if (medicineId != null) {
      for (final medicine in widget.controller.medicines) {
        if (medicine.id == medicineId) {
          _selectedMedicine = medicine;
          _loadHistory(medicineId);
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _product,
      _batch,
      _billed,
      _free,
      _mrp,
      _rate,
      _gst,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.94,
        child: Column(
          children: [
            _SheetHeader(
              title: widget.line == null ? 'Add purchase item' : 'Edit item',
              subtitle: 'Map against the catalog stored on this device',
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    24 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  children: [
                    TextFormField(
                      controller: _product,
                      autofocus: widget.line == null,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Supplier product name *',
                        prefixIcon: const Icon(Icons.medication_outlined),
                        suffixIcon: IconButton(
                          tooltip: 'Search local catalog',
                          onPressed: _searching ? null : _searchCatalog,
                          icon: _searching
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.manage_search_rounded),
                        ),
                      ),
                      validator: _required,
                      onFieldSubmitted: (_) => _searchCatalog(),
                    ),
                    const SizedBox(height: 10),
                    _CatalogMatchPanel(
                      candidates: _candidates,
                      selected: _selectedMedicine,
                      matchState: _matchState,
                      history: _history,
                      creating: _creating,
                      onSelected: _selectCandidate,
                      onCreate: _createCustomMedicine,
                      onSearch: _searchCatalog,
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 590;
                        final batch = TextFormField(
                          controller: _batch,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Batch number *',
                            prefixIcon: Icon(Icons.qr_code_2_rounded),
                          ),
                          validator: _required,
                        );
                        final expiry = _PickerField(
                          label: 'Expiry date',
                          value: formatDate(_expiry),
                          icon: Icons.event_outlined,
                          onTap: _pickExpiry,
                        );
                        return compact
                            ? Column(
                                children: [
                                  batch,
                                  const SizedBox(height: 12),
                                  expiry,
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: batch),
                                  const SizedBox(width: 12),
                                  Expanded(child: expiry),
                                ],
                              );
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _numberField(
                            _billed,
                            'Billed qty *',
                            Icons.inventory_2_outlined,
                            whole: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _numberField(
                            _free,
                            'Free qty',
                            Icons.card_giftcard_outlined,
                            whole: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _numberField(
                            _mrp,
                            'MRP (₹)',
                            Icons.sell_outlined,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _numberField(
                            _rate,
                            'Purchase rate (₹) *',
                            Icons.currency_rupee_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _numberField(_gst, 'GST percentage', Icons.percent_rounded),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(
                        widget.line == null ? 'Add purchase line' : 'Save line',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextFormField _numberField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool whole = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: !whole),
      inputFormatters: [
        if (whole)
          FilteringTextInputFormatter.digitsOnly
        else
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }

  Future<void> _searchCatalog() async {
    final query = _product.text.trim();
    if (query.isEmpty) {
      _showMessage('Enter the product name first.');
      return;
    }
    setState(() => _searching = true);
    try {
      final candidates = await widget.controller.findMedicineCandidates(query);
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        if (candidates.isEmpty) {
          _selectedMedicine = null;
          _matchState = 'unmatched';
          _matchScore = 0;
        } else {
          final first = candidates.first;
          final exact =
              first.medicine.name.trim().toLowerCase() == query.toLowerCase();
          _selectedMedicine = first.medicine;
          _matchState = exact ? 'exact' : 'partial';
          _matchScore = first.score;
          _loadHistory(first.medicine.id);
        }
      });
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectCandidate(Medicine medicine) {
    final candidate = _candidates
        .where((item) => item.medicine.id == medicine.id)
        .firstOrNull;
    setState(() {
      _selectedMedicine = medicine;
      _matchState =
          medicine.name.trim().toLowerCase() ==
              _product.text.trim().toLowerCase()
          ? 'exact'
          : 'manual';
      _matchScore = candidate?.score ?? 1;
      _history = null;
    });
    _loadHistory(medicine.id);
  }

  Future<void> _loadHistory(int? medicineId) async {
    if (medicineId == null) return;
    try {
      final history = await widget.controller.getLastPurchaseInfo(medicineId);
      if (mounted && _selectedMedicine?.id == medicineId) {
        setState(() => _history = history);
      }
    } catch (_) {
      // This is contextual guidance only.
    }
  }

  Future<void> _createCustomMedicine() async {
    final name = _product.text.trim();
    if (name.isEmpty) {
      _showMessage('Enter the custom medicine name first.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.add_box_outlined, color: AppColors.forest),
        title: const Text('Create local medicine?'),
        content: Text(
          '“$name” will be added to this device’s medicine catalog. You can enrich its details later from Stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create medicine'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _creating = true);
    try {
      final seed = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      final saved = await widget.controller.saveMedicine(
        Medicine(
          name: name,
          sku: _batch.text.trim().isNotEmpty
              ? _batch.text.trim()
              : 'CUSTOM-${seed.toUpperCase()}',
          branch: widget.branch,
          stock: 0,
          reorderThreshold: 0,
          costPaise: parseMoneyToPaise(_rate.text),
          pricePaise: parseMoneyToPaise(_mrp.text),
          expiryDate: _expiry,
        ),
      );
      if (!mounted) return;
      setState(() {
        _selectedMedicine = saved;
        _matchState = 'manual';
        _matchScore = 1;
        _candidates = [MedicineMatch(medicine: saved, score: 1)];
      });
      _showMessage('Custom medicine created locally.');
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? DateTime(now.year + 1),
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null && mounted) setState(() => _expiry = picked);
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final billed = int.tryParse(_billed.text) ?? 0;
    final free = int.tryParse(_free.text) ?? 0;
    if (billed + free <= 0) {
      _showMessage('Enter a billed or free quantity.', error: true);
      return;
    }
    Navigator.pop(
      context,
      PurchaseLine(
        id: widget.line?.id,
        purchaseId: widget.line?.purchaseId,
        medicineId: _selectedMedicine?.id,
        productName: _product.text.trim(),
        batchNumber: _batch.text.trim(),
        expiryDate: _expiry,
        billedQuantity: billed,
        freeQuantity: free,
        mrpPaise: parseMoneyToPaise(_mrp.text),
        purchaseRatePaise: parseMoneyToPaise(_rate.text),
        gstPercent: parsePercentage(_gst.text, maximum: 100),
        matchState: _selectedMedicine == null ? 'unmatched' : _matchState,
        matchScore: _selectedMedicine == null ? 0 : _matchScore,
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required' : null;

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error ? AppColors.danger : AppColors.ink,
          content: Text(message),
        ),
      );
  }
}

class _CatalogMatchPanel extends StatelessWidget {
  const _CatalogMatchPanel({
    required this.candidates,
    required this.selected,
    required this.matchState,
    required this.history,
    required this.creating,
    required this.onSelected,
    required this.onCreate,
    required this.onSearch,
  });

  final List<MedicineMatch> candidates;
  final Medicine? selected;
  final String matchState;
  final LastPurchaseInfo? history;
  final bool creating;
  final ValueChanged<Medicine> onSelected;
  final VoidCallback onCreate;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final visual = _matchVisual(matchState);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: visual.color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(visual.icon, color: visual.color, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${visual.label} • local catalog',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: visual.color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (candidates.isNotEmpty)
            DropdownButtonFormField<int>(
              initialValue: selected?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Matched medicine',
                prefixIcon: Icon(Icons.link_rounded),
                fillColor: Colors.white,
              ),
              items: candidates
                  .where((item) => item.medicine.id != null)
                  .map(
                    (item) => DropdownMenuItem<int>(
                      value: item.medicine.id,
                      child: Text(
                        '${item.medicine.name} • ${item.medicine.sku}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (id) {
                if (id == null) return;
                final medicine = candidates
                    .where((item) => item.medicine.id == id)
                    .firstOrNull
                    ?.medicine;
                if (medicine != null) onSelected(medicine);
              },
            )
          else
            Text(
              'Search to see likely medicines. If none fit, create a custom local catalog item.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.muted, height: 1.35),
            ),
          if (history != null) ...[
            const SizedBox(height: 10),
            Text(
              'Last purchase: ${formatMoney(history!.purchaseRatePaise)} • ${history!.supplierName} • ${formatDate(history!.invoiceDate)}',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: onSearch,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Search again'),
              ),
              TextButton.icon(
                onPressed: creating ? null : onCreate,
                icon: creating
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_box_outlined),
                label: const Text('Create custom'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupplierEditor extends StatefulWidget {
  const _SupplierEditor({required this.controller});

  final AppController controller;

  @override
  State<_SupplierEditor> createState() => _SupplierEditorState();
}

class _SupplierEditorState extends State<_SupplierEditor> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _gst = TextEditingController();
  final _address = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _gst.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
        child: Column(
          children: [
            const _SheetHeader(
              title: 'New supplier',
              subtitle: 'Stored privately on this device',
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    18,
                    16,
                    24 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  children: [
                    TextFormField(
                      controller: _name,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Supplier name *',
                        prefixIcon: Icon(Icons.local_shipping_outlined),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Supplier name is required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _gst,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'GST number',
                        prefixIcon: Icon(Icons.verified_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _address,
                      minLines: 2,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(_saving ? 'Saving…' : 'Create supplier'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.controller.saveSupplier(
        Supplier(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          gstNumber: _gst.text.trim(),
          address: _address.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, saved);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text(_friendlyError(error)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: enabled,
      label: '$label ${value.isEmpty ? 'not selected' : value}',
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
            enabled: enabled,
          ),
          child: Text(
            value.isEmpty ? 'Select date' : value,
            style: TextStyle(
              color: value.isEmpty ? AppColors.muted : AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingPurchases extends StatelessWidget {
  const _LoadingPurchases();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 300,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _MatchVisual {
  const _MatchVisual(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;
}

_MatchVisual _matchVisual(String state) {
  return switch (state) {
    'exact' => const _MatchVisual(
      'Exact match',
      AppColors.success,
      Icons.verified_rounded,
    ),
    'partial' => const _MatchVisual(
      'Partial match — review',
      AppColors.warning,
      Icons.rule_rounded,
    ),
    'manual' => const _MatchVisual(
      'Manually matched',
      AppColors.forest,
      Icons.link_rounded,
    ),
    _ => const _MatchVisual(
      'Unmatched',
      AppColors.danger,
      Icons.link_off_rounded,
    ),
  };
}

String _friendlyError(Object error) {
  return error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('StateError: ', '')
      .replaceFirst('FormatException: ', '');
}

String _normaliseHeader(String input) =>
    input.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

int _parseWhole(String input) {
  final value = double.tryParse(input.replaceAll(',', '').trim()) ?? 0;
  return value.clamp(0, 1 << 31).round();
}

double _parseNumber(String input) {
  final cleaned = input.replaceAll(RegExp('[^0-9.-]'), '');
  return double.tryParse(cleaned)?.clamp(0, 100).toDouble() ?? 0;
}

int _parseCsvMoney(String input) {
  final cleaned = input.replaceAll(RegExp('[^0-9.-]'), '');
  final value = double.tryParse(cleaned) ?? 0;
  return rupeesToPaise(value.clamp(0, double.infinity));
}

DateTime? _parseCsvDate(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;
  final direct = DateTime.tryParse(value);
  if (direct != null) return direct;
  for (final pattern in ['dd/MM/yyyy', 'dd-MM-yyyy', 'MM/yyyy', 'MM-yyyy']) {
    try {
      return DateFormat(pattern).parseStrict(value);
    } on FormatException {
      // Try the next common supplier format.
    }
  }
  return null;
}

String _trimDecimal(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

String _moneyInput(int paise) {
  final value = paise / 100;
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
