import 'package:flutter/material.dart';
import 'package:medistock_backend/medistock_backend.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';

class BranchOrdersScreen extends StatefulWidget {
  const BranchOrdersScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<BranchOrdersScreen> createState() => _BranchOrdersScreenState();
}

class _BranchOrdersScreenState extends State<BranchOrdersScreen> {
  String _filter = 'all';
  bool _acting = false;

  @override
  Widget build(BuildContext context) {
    final orders = widget.controller.branchOrders
        .where((order) => _filter == 'all' || order.status == _filter)
        .toList(growable: false);
    return RefreshIndicator(
      onRefresh: widget.controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 116),
        children: [
          SectionCard(
            title: 'Branch orders',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.controller.branchOrders.length} requests · '
                  '${widget.controller.branchOrders.where((order) => order.isRequested || order.isDispatched).length} active',
                  style: const TextStyle(
                    color: AppColors.forestDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Request stock during billing, then track dispatch and receipt here. '
                  'Orders are saved on this device and do not sync between devices.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (value, label) in <(String, String)>[
                  ('all', 'All'),
                  ('requested', 'Requested'),
                  ('dispatched', 'In transit'),
                  ('received', 'Received'),
                  ('cancelled', 'Cancelled'),
                ]) ...[
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == value,
                    onSelected: (_) => setState(() => _filter = value),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (orders.isEmpty)
            SectionCard(
              child: EmptyState(
                icon: Icons.local_shipping_outlined,
                title: _filter == 'all'
                    ? 'No branch orders yet'
                    : 'No orders in this status',
                message: _filter == 'all'
                    ? 'When a medicine is unavailable during billing, request it from a branch with stock.'
                    : 'Choose another status to see orders.',
              ),
            )
          else
            for (final order in orders) ...[
              _OrderCard(
                key: ValueKey('branch-order-${order.id}'),
                order: order,
                staffBranch: widget.controller.staffBranch,
                acting: _acting,
                onDispatch: () => _act(order, 'dispatch'),
                onReceive: () => _act(order, 'receive'),
                onCancel: () => _act(order, 'cancel'),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Future<void> _act(BranchOrder order, String action) async {
    final actionLabel = switch (action) {
      'dispatch' => 'Dispatch',
      'receive' => 'Receive',
      _ => 'Cancel',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$actionLabel order #${order.id}?'),
        content: Text(switch (action) {
          'dispatch' =>
            '${order.quantity} units will be removed from ${order.sourceBranch} stock.',
          'receive' =>
            '${order.quantity} units will be added to ${order.destinationBranch} stock.',
          _ => 'This request will be cancelled without changing stock.',
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _acting = true);
    try {
      switch (action) {
        case 'dispatch':
          await widget.controller.dispatchBranchOrder(order.id);
        case 'receive':
          await widget.controller.receiveBranchOrder(order.id);
        default:
          await widget.controller.cancelBranchOrder(order.id);
      }
      if (mounted) {
        final completedLabel = switch (action) {
          'dispatch' => 'dispatched',
          'receive' => 'received',
          _ => 'cancelled',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order #${order.id} $completedLabel.')),
        );
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
      if (mounted) setState(() => _acting = false);
    }
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    super.key,
    required this.order,
    required this.staffBranch,
    required this.acting,
    required this.onDispatch,
    required this.onReceive,
    required this.onCancel,
  });

  final BranchOrder order;
  final String? staffBranch;
  final bool acting;
  final VoidCallback onDispatch;
  final VoidCallback onReceive;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final canDispatch =
        order.isRequested &&
        (staffBranch == null || staffBranch == order.sourceBranch);
    final canReceive =
        order.isDispatched &&
        (staffBranch == null || staffBranch == order.destinationBranch);
    final canCancel = order.isRequested;
    final statusLabel = switch (order.status) {
      'requested' => 'Requested',
      'dispatched' => 'In transit',
      'received' => 'Received',
      _ => 'Cancelled',
    };
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.medicineName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Chip(label: Text(statusLabel)),
            ],
          ),
          Text(
            '${order.sku} · ${order.quantity} units · Order #${order.id}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Text(
            '${order.sourceBranch}  →  ${order.destinationBranch}',
            style: const TextStyle(
              color: AppColors.forestDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Requested ${formatDateTime(order.createdAt)} by ${order.requestedBy}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (order.dispatchedAt != null)
            Text(
              'Dispatched ${formatDateTime(order.dispatchedAt!)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          if (order.receivedAt != null)
            Text(
              'Received ${formatDateTime(order.receivedAt!)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          if (order.cancelledAt != null)
            Text(
              'Cancelled ${formatDateTime(order.cancelledAt!)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          if (canDispatch || canReceive || canCancel) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canDispatch)
                  FilledButton.icon(
                    onPressed: acting ? null : onDispatch,
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text('Dispatch'),
                  ),
                if (canReceive)
                  FilledButton.icon(
                    onPressed: acting ? null : onReceive,
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Receive stock'),
                  ),
                if (canCancel)
                  OutlinedButton(
                    onPressed: acting ? null : onCancel,
                    child: const Text('Cancel request'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
