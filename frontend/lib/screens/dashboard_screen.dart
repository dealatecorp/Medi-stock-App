import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
    required this.onNavigate,
  });

  final AppController controller;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final stats = controller.stats;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 116),
        children: [
          Text(
            'Overview',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Your pharmacy at a glance',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          _DashboardMetrics(
            totalMedicines: stats.totalMedicines,
            stockValuePaise: stats.stockValuePaise,
            lowStockCount: stats.lowStockCount,
            totalSalesPaise: stats.totalSalesPaise,
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Low quantity',
            trailing: TextButton(
              onPressed: () => onNavigate(1),
              child: const Text('Manage'),
            ),
            child: controller.lowStockMedicines.isEmpty
                ? const EmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'Stock levels look good',
                    message: 'No medicine is at or below its reorder level.',
                  )
                : Column(
                    children: [
                      for (
                        var i = 0;
                        i < controller.lowStockMedicines.length;
                        i++
                      ) ...[
                        Builder(
                          builder: (context) {
                            final medicine = controller.lowStockMedicines[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: AppColors.danger.withValues(
                                  alpha: 0.1,
                                ),
                                foregroundColor: AppColors.danger,
                                child: const Icon(Icons.medication_outlined),
                              ),
                              title: Text(
                                medicine.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${medicine.branch} · ${medicine.sku}',
                              ),
                              trailing: StockBadge(
                                stock: medicine.stock,
                                threshold: medicine.reorderThreshold,
                              ),
                              onTap: () => onNavigate(1),
                            );
                          },
                        ),
                        if (i < controller.lowStockMedicines.length - 1)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Recent invoices',
            trailing: TextButton(
              onPressed: () => onNavigate(3),
              child: const Text('View all'),
            ),
            child: controller.recentInvoices.isEmpty
                ? const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No invoices yet',
                    message: 'Saved bills will appear here.',
                  )
                : Column(
                    children: [
                      for (
                        var i = 0;
                        i < controller.recentInvoices.length;
                        i++
                      ) ...[
                        Builder(
                          builder: (context) {
                            final invoice = controller.recentInvoices[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                backgroundColor: AppColors.forestSoft,
                                foregroundColor: AppColors.forest,
                                child: Icon(Icons.receipt_outlined),
                              ),
                              title: Text(
                                invoice.number,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(invoice.customerName),
                              trailing: Text(
                                formatMoney(invoice.totalPaise),
                                style: const TextStyle(
                                  color: AppColors.forestDark,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              onTap: () => onNavigate(3),
                            );
                          },
                        ),
                        if (i < controller.recentInvoices.length - 1)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DashboardMetrics extends StatelessWidget {
  const _DashboardMetrics({
    required this.totalMedicines,
    required this.stockValuePaise,
    required this.lowStockCount,
    required this.totalSalesPaise,
  });

  final int totalMedicines;
  final int stockValuePaise;
  final int lowStockCount;
  final int totalSalesPaise;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      MetricCard(
        label: 'Total medicines',
        value: '$totalMedicines',
        icon: Icons.medication_outlined,
        prominent: true,
      ),
      MetricCard(
        label: 'Quantity value',
        value: formatMoney(stockValuePaise),
        icon: Icons.inventory_2_outlined,
        color: AppColors.gold,
      ),
      MetricCard(
        label: 'Low quantity',
        value: '$lowStockCount',
        icon: Icons.warning_amber_rounded,
        color: AppColors.danger,
      ),
      MetricCard(
        label: 'Total sales',
        value: formatMoney(totalSalesPaise),
        icon: Icons.receipt_long_outlined,
        color: AppColors.success,
        prominent: true,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 158,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: cards,
          );
        }

        return SizedBox(
          height: 274,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 4, child: cards[0]),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: cards[1]),
                          const SizedBox(width: 12),
                          Expanded(child: cards[2]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: cards[3]),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
