import 'package:flutter/material.dart';
import 'package:medistock_backend/medistock_backend.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';

class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  final Set<String> _updatingBranches = <String>{};

  Future<void> _refresh() async {
    try {
      await widget.controller.refresh();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not refresh branches: $error', isError: true);
    }
  }

  Future<void> _setBranchActive(BranchSummary branch, bool active) async {
    if (_updatingBranches.contains(branch.name)) return;

    if (!active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.pause_circle_outline_rounded,
            color: AppColors.warning,
          ),
          title: Text('Deactivate ${branch.name}?'),
          content: const Text(
            'The branch will be marked inactive and clearly separated from '
            'active operations. Its inventory and staff records remain safe.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep active'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _updatingBranches.add(branch.name));
    try {
      await widget.controller.setBranchActive(branch.name, active);
      if (!mounted) return;
      _showMessage('${branch.name} is now ${active ? 'active' : 'inactive'}.');
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not update ${branch.name}: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _updatingBranches.remove(branch.name));
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isError ? AppColors.danger : AppColors.forestDark,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final branches = widget.controller.branchSummaries;
    final showInitialLoader = widget.controller.busy && branches.isEmpty;
    final showInitialError =
        widget.controller.errorMessage != null && branches.isEmpty;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.forest,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 116),
        children: [
          const _PageHeading(),
          const SizedBox(height: 18),
          if (showInitialLoader)
            const _LoadingState()
          else if (showInitialError)
            _ErrorState(
              message: widget.controller.errorMessage!,
              onRetry: _refresh,
            )
          else if (branches.isEmpty)
            EmptyState(
              icon: Icons.store_mall_directory_outlined,
              title: 'No branches to monitor',
              message: 'Branch operations will appear here once configured.',
              action: OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
            )
          else ...[
            _PortfolioSummary(branches: branches),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'All branches',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _LiveIndicator(
                  activeCount: branches.where((item) => item.isActive).length,
                  totalCount: branches.length,
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 14.0;
                final columns = constraints.maxWidth >= 760 ? 2 : 1;
                final itemWidth =
                    (constraints.maxWidth - (gap * (columns - 1))) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final branch in branches)
                      SizedBox(
                        width: itemWidth,
                        child: _BranchCard(
                          branch: branch,
                          updating: _updatingBranches.contains(branch.name),
                          onActiveChanged: (active) =>
                              _setBranchActive(branch, active),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Branches',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Monitor operations, inventory health, and staff presence.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _PortfolioSummary extends StatelessWidget {
  const _PortfolioSummary({required this.branches});

  final List<BranchSummary> branches;

  @override
  Widget build(BuildContext context) {
    final active = branches.where((branch) => branch.isActive).length;
    final units = branches.fold<int>(
      0,
      (total, branch) => total + branch.totalUnits,
    );
    final staff = branches.fold<int>(
      0,
      (total, branch) => total + branch.activeStaffCount,
    );
    final checkIns = branches.fold<int>(
      0,
      (total, branch) => total + branch.todayCheckIns,
    );

    return Semantics(
      container: true,
      label:
          'Branch network summary. $active of ${branches.length} branches '
          'active, $units total units, $staff active staff, $checkIns check-ins '
          'today.',
      child: ExcludeSemantics(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.forestDark, AppColors.forest],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.forestDark.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              const Positioned(
                right: -42,
                top: -58,
                child: _DecorativeGlow(diameter: 180),
              ),
              const Positioned(
                left: 90,
                bottom: -88,
                child: _DecorativeGlow(diameter: 150),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: const Icon(
                            Icons.hub_outlined,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Branch network',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              Text(
                                '$checkIns staff check-ins today',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.72,
                                      ),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _HeroMetric(
                          label: 'Active',
                          value: '$active/${branches.length}',
                          icon: Icons.storefront_outlined,
                        ),
                        _HeroMetric(
                          label: 'Total units',
                          value: '$units',
                          icon: Icons.inventory_2_outlined,
                        ),
                        _HeroMetric(
                          label: 'Staff online',
                          value: '$staff',
                          icon: Icons.groups_2_outlined,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecorativeGlow extends StatelessWidget {
  const _DecorativeGlow({required this.diameter});

  final double diameter;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.13),
              Colors.white.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.68),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator({required this.activeCount, required this.totalCount});

  final int activeCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$activeCount of $totalCount branches are active',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.circle, size: 8, color: AppColors.success),
              const SizedBox(width: 6),
              Text(
                '$activeCount active',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.updating,
    required this.onActiveChanged,
  });

  final BranchSummary branch;
  final bool updating;
  final ValueChanged<bool> onActiveChanged;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final active = branch.isActive;
    final accent = active ? AppColors.forest : AppColors.muted;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: AnimatedContainer(
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: active ? 0.055 : 0.025),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: active
                        ? [
                            AppColors.forestSoft,
                            AppColors.forestSoft.withValues(alpha: 0.25),
                          ]
                        : [
                            AppColors.muted.withValues(alpha: 0.1),
                            AppColors.muted.withValues(alpha: 0.035),
                          ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.forest.withValues(alpha: 0.12)
                            : AppColors.muted.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.storefront_rounded,
                        color: accent,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            branch.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 4),
                          _StatusBadge(active: active),
                        ],
                      ),
                    ),
                    if (updating)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      )
                    else
                      Semantics(
                        label:
                            '${active ? 'Deactivate' : 'Activate'} ${branch.name}',
                        toggled: active,
                        child: Switch.adaptive(
                          value: active,
                          activeTrackColor: AppColors.forest,
                          onChanged: onActiveChanged,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 10.0;
                        final cellWidth = (constraints.maxWidth - spacing) / 2;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            _BranchStat(
                              width: cellWidth,
                              icon: Icons.medication_outlined,
                              label: 'Medicine rows',
                              value: '${branch.medicineCount}',
                            ),
                            _BranchStat(
                              width: cellWidth,
                              icon: Icons.inventory_2_outlined,
                              label: 'Total units',
                              value: '${branch.totalUnits}',
                            ),
                            _BranchStat(
                              width: cellWidth,
                              icon: Icons.warning_amber_rounded,
                              label: 'Low stock',
                              value: '${branch.lowStockCount}',
                              color: branch.lowStockCount > 0
                                  ? AppColors.danger
                                  : AppColors.success,
                            ),
                            _BranchStat(
                              width: cellWidth,
                              icon: Icons.account_balance_wallet_outlined,
                              label: 'Inventory value',
                              value: formatMoney(branch.stockValuePaise),
                              color: AppColors.gold,
                            ),
                            _BranchStat(
                              width: cellWidth,
                              icon: Icons.badge_outlined,
                              label: 'Active staff',
                              value: '${branch.activeStaffCount}',
                            ),
                            _BranchStat(
                              width: cellWidth,
                              icon: Icons.how_to_reg_outlined,
                              label: "Today's check-ins",
                              value: '${branch.todayCheckIns}',
                              color: AppColors.success,
                            ),
                          ],
                        );
                      },
                    ),
                    if (!active) ...[
                      const SizedBox(height: 13),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: AppColors.warning,
                              size: 19,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Operations are currently paused.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
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
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : AppColors.muted;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 7, color: color),
            const SizedBox(width: 5),
            Text(
              active ? 'Active' : 'Inactive',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchStat extends StatelessWidget {
  const _BranchStat({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    this.color = AppColors.forest,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Container(
          width: width,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.065),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: color.withValues(alpha: 0.09)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      label,
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
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: Center(
        child: Semantics(
          label: 'Loading branch statistics',
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Branch data is unavailable',
      message: message,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try again'),
      ),
    );
  }
}
