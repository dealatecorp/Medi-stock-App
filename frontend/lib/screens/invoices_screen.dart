import 'package:flutter/material.dart';
import 'package:medistock_backend/medistock_backend.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../services/invoice_pdf_service.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _activeAction;

  List<InvoiceRecord> get _filteredInvoices {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.controller.invoices.toList(growable: false);
    }

    return widget.controller.invoices
        .where((invoice) {
          final searchable = <String>[
            invoice.number,
            invoice.customerName,
            invoice.customerPhone,
            for (final item in invoice.items) ...[item.medicineName, item.sku],
          ].join(' ').toLowerCase();
          return searchable.contains(query);
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
    final invoices = _filteredInvoices;
    final hasInvoices = widget.controller.invoices.isNotEmpty;
    final isInitialLoad = widget.controller.busy && !hasInvoices;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 116),
        children: [
          Text(
            'Invoice history',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Find, review, print, or share any saved bill',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          _InvoiceOverview(invoices: widget.controller.invoices),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              labelText: 'Search invoices',
              hintText: 'Invoice, patient, phone, or medicine',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          if (widget.controller.busy && hasInvoices) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: const LinearProgressIndicator(minHeight: 3),
            ),
          ],
          if (widget.controller.errorMessage != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(
              message: _friendlyError(widget.controller.errorMessage!),
              onRetry: _refresh,
            ),
          ],
          const SizedBox(height: 16),
          if (isInitialLoad)
            const _LoadingInvoices()
          else if (invoices.isEmpty)
            SectionCard(
              child: EmptyState(
                icon: _query.isEmpty
                    ? Icons.receipt_long_outlined
                    : Icons.search_off_rounded,
                title: _query.isEmpty
                    ? 'No invoices yet'
                    : 'No matching invoices',
                message: _query.isEmpty
                    ? 'Create and save a bill to see it here.'
                    : 'Try a patient name, phone number, invoice number, or medicine.',
                action: _query.isEmpty
                    ? null
                    : TextButton.icon(
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Clear search'),
                      ),
              ),
            )
          else
            Column(
              children: [
                _ResultsLabel(
                  count: invoices.length,
                  isFiltered: _query.trim().isNotEmpty,
                ),
                const SizedBox(height: 10),
                for (var index = 0; index < invoices.length; index++) ...[
                  _InvoiceCard(
                    key: ValueKey(invoices[index].id ?? invoices[index].number),
                    invoice: invoices[index],
                    printing:
                        _activeAction == '${invoices[index].number}:print',
                    sharing: _activeAction == '${invoices[index].number}:share',
                    actionsEnabled: _activeAction == null,
                    onPrint: () => _printInvoice(invoices[index]),
                    onShare: () => _shareInvoice(invoices[index]),
                  ),
                  if (index < invoices.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  Future<void> _refresh() async {
    try {
      await widget.controller.refresh();
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    }
  }

  Future<void> _printInvoice(InvoiceRecord invoice) async {
    final action = '${invoice.number}:print';
    setState(() => _activeAction = action);
    try {
      await InvoicePdfService.printInvoice(invoice);
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    } finally {
      if (mounted && _activeAction == action) {
        setState(() => _activeAction = null);
      }
    }
  }

  Future<void> _shareInvoice(InvoiceRecord invoice) async {
    final action = '${invoice.number}:share';
    setState(() => _activeAction = action);
    try {
      await InvoicePdfService.shareInvoice(invoice);
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    } finally {
      if (mounted && _activeAction == action) {
        setState(() => _activeAction = null);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _InvoiceOverview extends StatelessWidget {
  const _InvoiceOverview({required this.invoices});

  final Iterable<InvoiceRecord> invoices;

  @override
  Widget build(BuildContext context) {
    final invoiceList = invoices.toList(growable: false);
    final revenue = invoiceList.fold<int>(
      0,
      (total, invoice) => total + invoice.totalPaise,
    );
    final units = invoiceList.fold<int>(
      0,
      (total, invoice) => total + invoice.totalQuantity,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
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
              top: -48,
              right: -28,
              child: _GlowOrb(
                size: 150,
                color: AppColors.gold.withValues(alpha: 0.19),
              ),
            ),
            Positioned(
              bottom: -58,
              left: 42,
              child: _GlowOrb(
                size: 130,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(9),
                          child: Icon(
                            Icons.insights_rounded,
                            color: Colors.white,
                            size: 21,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Billing snapshot',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Saved securely on this device',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth = constraints.maxWidth >= 480
                          ? (constraints.maxWidth - 20) / 3
                          : (constraints.maxWidth - 10) / 2;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _OverviewTile(
                            width: itemWidth,
                            label: 'Invoices',
                            value: '${invoiceList.length}',
                          ),
                          _OverviewTile(
                            width: itemWidth,
                            label: 'Revenue',
                            value: formatMoney(revenue),
                          ),
                          _OverviewTile(
                            width: itemWidth,
                            label: 'Items sold',
                            value: '$units',
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.width,
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ResultsLabel extends StatelessWidget {
  const _ResultsLabel({required this.count, required this.isFiltered});

  final int count;
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          isFiltered ? 'Search results' : 'All invoices',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.forestSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              '$count ${count == 1 ? 'invoice' : 'invoices'}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.forestDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    super.key,
    required this.invoice,
    required this.printing,
    required this.sharing,
    required this.actionsEnabled,
    required this.onPrint,
    required this.onShare,
  });

  final InvoiceRecord invoice;
  final bool printing;
  final bool sharing;
  final bool actionsEnabled;
  final VoidCallback onPrint;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final patient = invoice.customerName.trim().isEmpty
        ? 'Walk-in patient'
        : invoice.customerName.trim();
    final phone = invoice.customerPhone.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: AppColors.forest.withValues(alpha: 0.06),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          childrenPadding: EdgeInsets.zero,
          leading: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.forestSoft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const SizedBox.square(
              dimension: 44,
              child: Icon(Icons.receipt_outlined, color: AppColors.forest),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  invoice.number,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatMoney(invoice.totalPaise),
                style: const TextStyle(
                  color: AppColors.forestDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phone.isEmpty ? patient : '$patient • $phone',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDateTime(invoice.createdAt)} • '
                  '${invoice.totalQuantity} ${invoice.totalQuantity == 1 ? 'item' : 'items'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          children: [
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Bill items',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${invoice.items.length} lines',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (invoice.items.isEmpty)
                    Text(
                      'No line items stored for this invoice.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: AppColors.muted),
                    )
                  else
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.canvas,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 4,
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < invoice.items.length; i++) ...[
                              _InvoiceItemRow(item: invoice.items[i]),
                              if (i < invoice.items.length - 1)
                                const Divider(height: 1),
                            ],
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  _InvoiceTotals(invoice: invoice),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: actionsEnabled ? onPrint : null,
                          icon: printing
                              ? const SizedBox.square(
                                  dimension: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.print_outlined),
                          label: Text(printing ? 'Preparing…' : 'Print'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: actionsEnabled ? onShare : null,
                          icon: sharing
                              ? const SizedBox.square(
                                  dimension: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.share_outlined),
                          label: Text(sharing ? 'Preparing…' : 'Share PDF'),
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
}

class _InvoiceItemRow extends StatelessWidget {
  const _InvoiceItemRow({required this.item});

  final InvoiceItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.medicineName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.sku} • ${item.quantity} × '
                  '${formatMoney(item.unitPricePaise)}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatMoney(item.lineTotalPaise),
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceTotals extends StatelessWidget {
  const _InvoiceTotals({required this.invoice});

  final InvoiceRecord invoice;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.forest.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _TotalLine(label: 'Subtotal', value: invoice.subtotalPaise),
            const SizedBox(height: 8),
            _TotalLine(label: 'Tax', value: invoice.taxPaise),
            const SizedBox(height: 8),
            _TotalLine(label: 'Discount', value: -invoice.discountPaise),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  formatMoney(invoice.totalPaise),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.forest,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted)),
        Text(
          formatMoney(value),
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _LoadingInvoices extends StatelessWidget {
  const _LoadingInvoices();

  @override
  Widget build(BuildContext context) {
    return const SectionCard(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 34),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text(
                'Loading invoices…',
                style: TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String _friendlyError(Object error) => error
    .toString()
    .replaceFirst('Exception: ', '')
    .replaceFirst('Bad state: ', '')
    .replaceFirst('Invalid argument(s): ', '');
