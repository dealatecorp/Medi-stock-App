import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:medistock_backend/medistock_backend.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../services/report_export_service.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _ReportPeriod _period = _ReportPeriod.last30Days;
  String? _exporting;

  List<InvoiceRecord> get _invoices {
    final start = _period.startDate;
    return widget.controller.invoices
        .where(
          (invoice) =>
              start == null || !invoice.createdAt.toLocal().isBefore(start),
        )
        .toList(growable: false);
  }

  List<PurchaseRecord> get _purchases {
    final start = _period.startDate;
    return widget.controller.purchases
        .where(
          (purchase) =>
              start == null || !purchase.invoiceDate.toLocal().isBefore(start),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final invoices = _invoices;
    final purchases = _purchases;
    final sales = _SalesSummary.from(invoices);
    final purchaseSummary = _PurchaseSummary.from(purchases);
    final expiry = _ExpirySummary.from(widget.controller.medicines);
    final netGst = sales.outputGstPaise - purchaseSummary.inputGstPaise;

    return RefreshIndicator(
      onRefresh: widget.controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 116),
        children: [
          Text(
            'Reports',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Clear financial and stock insights, stored on this device',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          _PeriodSelector(
            selected: _period,
            onSelected: (period) => setState(() => _period = period),
          ),
          const SizedBox(height: 16),
          _Reveal(
            order: 0,
            child: _ReportHero(
              label: _period.label,
              revenuePaise: sales.revenuePaise,
              profitPaise: sales.profitPaise,
              invoices: invoices.length,
              netGstPaise: netGst,
            ),
          ),
          const SizedBox(height: 16),
          _Reveal(
            order: 1,
            child: _SalesLedgerCard(
              invoices: invoices,
              summary: sales,
              exporting: _exporting == 'sales',
              onExport: () => _export(
                key: 'sales',
                action: () => ReportExportService.shareSales(
                  invoices: invoices,
                  periodLabel: _period.label,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Reveal(
            order: 2,
            child: _PurchaseLedgerCard(
              purchases: purchases,
              summary: purchaseSummary,
              exporting: _exporting == 'purchases',
              onExport: () => _export(
                key: 'purchases',
                action: () => ReportExportService.sharePurchases(
                  purchases: purchases,
                  periodLabel: _period.label,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Reveal(
            order: 3,
            child: _GstCard(
              sales: sales,
              purchases: purchaseSummary,
              exporting: _exporting == 'gst',
              onExport: () => _export(
                key: 'gst',
                action: () => ReportExportService.shareGst(
                  invoices: invoices,
                  purchases: purchases,
                  periodLabel: _period.label,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Reveal(
            order: 4,
            child: _ExpiryAuditCard(
              summary: expiry,
              exporting: _exporting == 'expiry',
              onExport: () => _export(
                key: 'expiry',
                action: () => ReportExportService.shareExpiry(
                  medicines: widget.controller.medicines.toList(
                    growable: false,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export({
    required String key,
    required Future<Object?> Function() action,
  }) async {
    if (_exporting != null) return;
    setState(() => _exporting = key);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not export report: ${_friendlyError(error)}'),
            backgroundColor: AppColors.danger,
          ),
        );
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }
}

enum _ReportPeriod {
  today('Today', 0),
  last7Days('7 days', 6),
  last30Days('30 days', 29),
  allTime('All time', null);

  const _ReportPeriod(this.label, this.daysBack);

  final String label;
  final int? daysBack;

  DateTime? get startDate {
    final days = daysBack;
    if (days == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: days));
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.selected, required this.onSelected});

  final _ReportPeriod selected;
  final ValueChanged<_ReportPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final period in _ReportPeriod.values) ...[
            ChoiceChip(
              selected: selected == period,
              label: Text(period.label),
              avatar: selected == period
                  ? const Icon(Icons.check_rounded, size: 17)
                  : null,
              onSelected: (_) => onSelected(period),
              selectedColor: AppColors.forestSoft,
              side: BorderSide(
                color: selected == period
                    ? AppColors.forest.withValues(alpha: 0.3)
                    : AppColors.muted.withValues(alpha: 0.18),
              ),
              labelStyle: TextStyle(
                color: selected == period
                    ? AppColors.forestDark
                    : AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (period != _ReportPeriod.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ReportHero extends StatelessWidget {
  const _ReportHero({
    required this.label,
    required this.revenuePaise,
    required this.profitPaise,
    required this.invoices,
    required this.netGstPaise,
  });

  final String label;
  final int revenuePaise;
  final int profitPaise;
  final int invoices;
  final int netGstPaise;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.forestDark, AppColors.forest],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.forest.withValues(alpha: 0.2),
            blurRadius: 25,
            offset: const Offset(0, 11),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -56,
            top: -72,
            child: _GlowOrb(size: 210, color: Color(0x36FFFFFF)),
          ),
          const Positioned(
            left: -64,
            bottom: -88,
            child: _GlowOrb(size: 180, color: Color(0x28E2B35A)),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
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
                            'Net sales',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            formatMoney(revenuePaise),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.7,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = (constraints.maxWidth - 16) / 3;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeroMetric(
                          width: width,
                          label: 'Gross profit',
                          value: formatMoney(profitPaise),
                        ),
                        const SizedBox(width: 8),
                        _HeroMetric(
                          width: width,
                          label: 'Invoices',
                          value: '$invoices',
                        ),
                        const SizedBox(width: 8),
                        _HeroMetric(
                          width: width,
                          label: 'Net GST',
                          value: formatMoney(netGstPaise),
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
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _SalesLedgerCard extends StatelessWidget {
  const _SalesLedgerCard({
    required this.invoices,
    required this.summary,
    required this.exporting,
    required this.onExport,
  });

  final List<InvoiceRecord> invoices;
  final _SalesSummary summary;
  final bool exporting;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Sales ledger',
      trailing: _ExportButton(
        exporting: exporting,
        enabled: invoices.isNotEmpty,
        onPressed: onExport,
      ),
      child: Column(
        children: [
          _MetricStrip(
            metrics: [
              _MetricData('Revenue', formatMoney(summary.revenuePaise)),
              _MetricData('COGS', formatMoney(summary.cogsPaise)),
              _MetricData(
                'Profit',
                formatMoney(summary.profitPaise),
                color: summary.profitPaise >= 0
                    ? AppColors.success
                    : AppColors.danger,
              ),
              _MetricData(
                'Margin',
                '${summary.marginPercent.toStringAsFixed(1)}%',
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (invoices.isEmpty)
            const EmptyState(
              icon: Icons.query_stats_rounded,
              title: 'No sales in this period',
              message: 'Choose a wider range or create an invoice.',
            )
          else
            _LedgerList(
              remaining: math.max(0, invoices.length - 5),
              itemName: 'invoice',
              children: [
                for (final invoice in invoices.take(5))
                  _LedgerRow(
                    icon: Icons.receipt_long_outlined,
                    title: invoice.number,
                    subtitle:
                        '${invoice.customerName} · ${formatDate(invoice.createdAt)}',
                    value: formatMoney(_salesRevenue(invoice)),
                    footnote: 'Profit ${formatMoney(_invoiceProfit(invoice))}',
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PurchaseLedgerCard extends StatelessWidget {
  const _PurchaseLedgerCard({
    required this.purchases,
    required this.summary,
    required this.exporting,
    required this.onExport,
  });

  final List<PurchaseRecord> purchases;
  final _PurchaseSummary summary;
  final bool exporting;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Purchase ledger',
      trailing: _ExportButton(
        exporting: exporting,
        enabled: purchases.isNotEmpty,
        onPressed: onExport,
      ),
      child: Column(
        children: [
          _MetricStrip(
            metrics: [
              _MetricData('COGS', formatMoney(summary.cogsPaise)),
              _MetricData('Input GST', formatMoney(summary.inputGstPaise)),
              _MetricData('Payable', formatMoney(summary.payablePaise)),
              _MetricData('Drafts', '${summary.draftCount}'),
            ],
          ),
          const SizedBox(height: 14),
          if (purchases.isEmpty)
            const EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'No purchases in this period',
              message: 'Completed and draft supplier invoices appear here.',
            )
          else
            _LedgerList(
              remaining: math.max(0, purchases.length - 5),
              itemName: 'purchase',
              children: [
                for (final purchase in purchases.take(5))
                  _LedgerRow(
                    icon: purchase.status == 'completed'
                        ? Icons.inventory_2_outlined
                        : Icons.edit_note_rounded,
                    title: purchase.invoiceNumber,
                    subtitle:
                        '${purchase.supplierName} · ${formatDate(purchase.invoiceDate)}',
                    value: formatMoney(purchase.totalPaise),
                    footnote: purchase.status == 'completed'
                        ? '${purchase.lines.length} lines · Completed'
                        : '${purchase.lines.length} lines · Draft',
                    muted: purchase.status != 'completed',
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _GstCard extends StatelessWidget {
  const _GstCard({
    required this.sales,
    required this.purchases,
    required this.exporting,
    required this.onExport,
  });

  final _SalesSummary sales;
  final _PurchaseSummary purchases;
  final bool exporting;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final net = sales.outputGstPaise - purchases.inputGstPaise;
    return SectionCard(
      title: 'GST summary',
      trailing: _ExportButton(
        exporting: exporting,
        enabled: sales.invoiceCount > 0 || purchases.completedCount > 0,
        onPressed: onExport,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _TaxTile(
                  icon: Icons.north_east_rounded,
                  label: 'Output GST',
                  value: formatMoney(sales.outputGstPaise),
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TaxTile(
                  icon: Icons.south_west_rounded,
                  label: 'Input GST',
                  value: formatMoney(purchases.inputGstPaise),
                  color: AppColors.forest,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (net >= 0 ? AppColors.gold : AppColors.success).withValues(
                alpha: 0.08,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: (net >= 0 ? AppColors.gold : AppColors.success)
                    .withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        net >= 0 ? 'Estimated GST payable' : 'Estimated credit',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatMoney(net.abs()),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Output GST minus input GST. Verify with your tax advisor.',
                  child: Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.muted.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Planning estimate only · exported records retain the underlying '
              'sales and purchase references.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.muted, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpiryAuditCard extends StatelessWidget {
  const _ExpiryAuditCard({
    required this.summary,
    required this.exporting,
    required this.onExport,
  });

  final _ExpirySummary summary;
  final bool exporting;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Expiry audit',
      trailing: _ExportButton(
        exporting: exporting,
        enabled: summary.datedMedicines.isNotEmpty,
        onPressed: onExport,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ExpiryTile(
                  label: 'Expired',
                  count: summary.expired.length,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ExpiryTile(
                  label: '< 3 months',
                  count: summary.under3Months.length,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ExpiryTile(
                  label: '3–6 months',
                  count: summary.threeTo6Months.length,
                  color: AppColors.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (summary.attention.isEmpty)
            const EmptyState(
              icon: Icons.event_available_outlined,
              title: 'No near-term expiry risk',
              message: 'No dated stock expires in the next six months.',
            )
          else
            _LedgerList(
              remaining: math.max(0, summary.attention.length - 6),
              itemName: 'medicine',
              children: [
                for (final medicine in summary.attention.take(6))
                  _LedgerRow(
                    icon: Icons.event_busy_outlined,
                    title: medicine.name,
                    subtitle:
                        '${medicine.branch} · ${medicine.sku} · Qty ${medicine.stock}',
                    value: _expiryLabel(medicine.expiryDate!),
                    footnote: formatDate(medicine.expiryDate),
                    danger: medicine.expiryDate!.isBefore(summary.today),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.metrics});

  final List<_MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 4 : 2;
        final width = (constraints.maxWidth - ((columns - 1) * 8)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final metric in metrics)
              Container(
                width: width,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: AppColors.muted.withValues(alpha: 0.1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: metric.color ?? AppColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      metric.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetricData {
  const _MetricData(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;
}

class _LedgerList extends StatelessWidget {
  const _LedgerList({
    required this.children,
    required this.remaining,
    required this.itemName,
  });

  final List<Widget> children;
  final int remaining;
  final String itemName;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.muted.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index < children.length - 1) const Divider(height: 1),
            ],
            if (remaining > 0) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Text(
                  '+$remaining more ${remaining == 1 ? itemName : '${itemName}s'} in CSV',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.forest,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.footnote,
    this.muted = false,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final String footnote;
  final bool muted;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? AppColors.danger
        : muted
        ? AppColors.muted
        : AppColors.forest;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                footnote,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.exporting,
    required this.enabled,
    required this.onPressed,
  });

  final bool exporting;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: enabled && !exporting ? onPressed : null,
      icon: exporting
          ? const SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.ios_share_rounded, size: 17),
      label: Text(exporting ? 'Preparing' : 'CSV'),
    );
  }
}

class _TaxTile extends StatelessWidget {
  const _TaxTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium
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

class _ExpiryTile extends StatelessWidget {
  const _ExpiryTile({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: color, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SalesSummary {
  const _SalesSummary({
    required this.invoiceCount,
    required this.revenuePaise,
    required this.cogsPaise,
    required this.profitPaise,
    required this.outputGstPaise,
  });

  factory _SalesSummary.from(List<InvoiceRecord> invoices) {
    final revenue = invoices.fold<int>(0, (sum, item) {
      return sum + _salesRevenue(item);
    });
    final cogs = invoices.fold<int>(0, (sum, item) {
      return sum + _invoiceCogs(item);
    });
    return _SalesSummary(
      invoiceCount: invoices.length,
      revenuePaise: revenue,
      cogsPaise: cogs,
      profitPaise: revenue - cogs,
      outputGstPaise: invoices.fold<int>(0, (sum, item) => sum + item.taxPaise),
    );
  }

  final int invoiceCount;
  final int revenuePaise;
  final int cogsPaise;
  final int profitPaise;
  final int outputGstPaise;

  double get marginPercent =>
      revenuePaise <= 0 ? 0 : (profitPaise * 100 / revenuePaise);
}

class _PurchaseSummary {
  const _PurchaseSummary({
    required this.completedCount,
    required this.draftCount,
    required this.cogsPaise,
    required this.inputGstPaise,
    required this.payablePaise,
  });

  factory _PurchaseSummary.from(List<PurchaseRecord> purchases) {
    final completed = purchases
        .where((purchase) => purchase.status == 'completed')
        .toList(growable: false);
    return _PurchaseSummary(
      completedCount: completed.length,
      draftCount: purchases.length - completed.length,
      cogsPaise: completed.fold<int>(
        0,
        (sum, purchase) => sum + purchase.subtotalPaise,
      ),
      inputGstPaise: completed.fold<int>(
        0,
        (sum, purchase) => sum + purchase.gstPaise,
      ),
      payablePaise: completed.fold<int>(
        0,
        (sum, purchase) => sum + purchase.totalPaise,
      ),
    );
  }

  final int completedCount;
  final int draftCount;
  final int cogsPaise;
  final int inputGstPaise;
  final int payablePaise;
}

class _ExpirySummary {
  _ExpirySummary._({
    required this.today,
    required this.datedMedicines,
    required this.expired,
    required this.under3Months,
    required this.threeTo6Months,
    required this.attention,
  });

  factory _ExpirySummary.from(Iterable<Medicine> medicines) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final threeMonths = _addMonths(today, 3);
    final sixMonths = _addMonths(today, 6);
    final dated =
        medicines
            .where((medicine) => medicine.expiryDate != null)
            .toList(growable: false)
          ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
    final expired = dated
        .where((medicine) => medicine.expiryDate!.isBefore(today))
        .toList(growable: false);
    final under3 = dated
        .where(
          (medicine) =>
              !medicine.expiryDate!.isBefore(today) &&
              medicine.expiryDate!.isBefore(threeMonths),
        )
        .toList(growable: false);
    final threeTo6 = dated
        .where(
          (medicine) =>
              !medicine.expiryDate!.isBefore(threeMonths) &&
              medicine.expiryDate!.isBefore(sixMonths),
        )
        .toList(growable: false);
    return _ExpirySummary._(
      today: today,
      datedMedicines: dated,
      expired: expired,
      under3Months: under3,
      threeTo6Months: threeTo6,
      attention: <Medicine>[...expired, ...under3, ...threeTo6],
    );
  }

  final DateTime today;
  final List<Medicine> datedMedicines;
  final List<Medicine> expired;
  final List<Medicine> under3Months;
  final List<Medicine> threeTo6Months;
  final List<Medicine> attention;
}

class _Reveal extends StatefulWidget {
  const _Reveal({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = curve;
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(curve);
    Future<void>.delayed(Duration(milliseconds: widget.order * 55), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
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

int _invoiceCogs(InvoiceRecord invoice) => invoice.items.fold<int>(
  0,
  (sum, item) => sum + (item.costPaise * item.quantity),
);

int _salesRevenue(InvoiceRecord invoice) =>
    (invoice.subtotalPaise - invoice.discountPaise).clamp(0, 1 << 62).toInt();

int _invoiceProfit(InvoiceRecord invoice) =>
    _salesRevenue(invoice) - _invoiceCogs(invoice);

String _expiryLabel(DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(value.year, value.month, value.day);
  if (date.isBefore(today)) return 'Expired';
  if (date.isBefore(_addMonths(today, 3))) return '< 3 months';
  return '3–6 months';
}

DateTime _addMonths(DateTime value, int months) {
  final targetMonth = value.month + months;
  final year = value.year + (targetMonth - 1) ~/ 12;
  final month = (targetMonth - 1) % 12 + 1;
  final finalDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, value.day.clamp(1, finalDay));
}

String _friendlyError(Object error) => error
    .toString()
    .replaceFirst('Exception: ', '')
    .replaceFirst('Bad state: ', '')
    .replaceFirst('Invalid argument(s): ', '');
