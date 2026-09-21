import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../state/app_controller.dart';
import 'branches_screen.dart';
import 'dashboard_screen.dart';
import 'inventory_screen.dart';
import 'purchases_screen.dart';
import 'reports_screen.dart';
import 'sales_screen.dart';
import 'staff_screen.dart';
import 'support_screen.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.controller});

  final AppController controller;

  static const _destinations = <_AppDestination>[
    _AppDestination(
      label: 'Overview',
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard_rounded,
      subtitle: 'Pharmacy overview',
    ),
    _AppDestination(
      label: 'Inventory',
      icon: Icons.shopping_bag_outlined,
      selectedIcon: Icons.shopping_bag_rounded,
      subtitle: 'Suppliers and stock intake',
    ),
    _AppDestination(
      label: 'Stock',
      icon: Icons.medication_outlined,
      selectedIcon: Icons.medication_rounded,
      subtitle: 'Inventory and expiry',
    ),
    _AppDestination(
      label: 'Sales',
      icon: Icons.point_of_sale_outlined,
      selectedIcon: Icons.point_of_sale_rounded,
      subtitle: 'Billing and invoice history',
    ),
    _AppDestination(
      label: 'Reports',
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics_rounded,
      subtitle: 'Ledgers, GST, and expiry',
    ),
    _AppDestination(
      label: 'Support',
      icon: Icons.support_agent_outlined,
      selectedIcon: Icons.support_agent_rounded,
      subtitle: 'Help and system status',
    ),
  ];

  static const _branchesDestination = _AppDestination(
    label: 'Branches',
    icon: Icons.store_mall_directory_outlined,
    selectedIcon: Icons.store_mall_directory_rounded,
    subtitle: 'Branch health and activity',
  );

  static const _staffDestination = _AppDestination(
    label: 'Staff',
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups_rounded,
    subtitle: 'Team and daily check-ins',
  );

  static const _adminDestinations = <_AppDestination>[
    ..._destinations,
    _branchesDestination,
    _staffDestination,
  ];

  static const _moreDestination = _AppDestination(
    label: 'More',
    icon: Icons.grid_view_outlined,
    selectedIcon: Icons.grid_view_rounded,
    subtitle: 'Reports, support, and administration',
  );

  @override
  Widget build(BuildContext context) {
    final destinations = controller.isAdmin
        ? _adminDestinations
        : _destinations;
    return LayoutBuilder(
      builder: (context, constraints) {
        final useWideNavigation = constraints.maxWidth >= 900;
        if (useWideNavigation) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  _WideNavigation(
                    destinations: destinations,
                    selectedIndex: controller.selectedIndex,
                    onDestinationSelected: controller.selectTab,
                    onAction: (action) => _handleAction(context, action),
                    isAdmin: controller.isAdmin,
                    userName: controller.currentUserName,
                    userSubtitle: controller.currentUserSubtitle,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _WorkspaceHeader(
                          destination: destinations[controller.selectedIndex],
                          busy: controller.busy,
                          isAdmin: controller.isAdmin,
                          onRefresh: () =>
                              _handleAction(context, _AppAction.refresh),
                          onAction: (action) => _handleAction(context, action),
                        ),
                        Expanded(child: _WorkspaceBody(controller: controller)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            floatingActionButton: _buildFloatingActionButton(context),
          );
        }

        final destination = destinations[controller.selectedIndex];
        final mobileDestinations = <_AppDestination>[
          ..._destinations.take(4),
          _moreDestination,
        ];
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 72,
            titleSpacing: 18,
            title: Row(
              children: [
                const _CompactLogo(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        destination.label,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.25,
                        ),
                      ),
                      Text(
                        destination.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: controller.busy
                    ? null
                    : () => _handleAction(context, _AppAction.refresh),
                icon: const Icon(Icons.refresh_rounded),
              ),
              _ActionMenu(
                enabled: !controller.busy,
                isAdmin: controller.isAdmin,
                onSelected: (action) => _handleAction(context, action),
              ),
              const SizedBox(width: 6),
            ],
            bottom: controller.busy
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(3),
                    child: LinearProgressIndicator(minHeight: 3),
                  )
                : null,
          ),
          body: _WorkspaceBody(controller: controller),
          bottomNavigationBar: _MobileCommandDock(
            destinations: mobileDestinations,
            selectedIndex: controller.selectedIndex >= 4
                ? 4
                : controller.selectedIndex,
            enabled: !controller.busy,
            onSelected: (index) {
              if (index == 4) {
                _showMoreNavigationSheet(context, destinations);
              } else {
                controller.selectTab(index);
              }
            },
          ),
          floatingActionButton: _buildFloatingActionButton(context),
        );
      },
    );
  }

  Future<void> _showMoreNavigationSheet(
    BuildContext context,
    List<_AppDestination> destinations,
  ) async {
    final indices = <int>[
      4,
      5,
      if (controller.isAdmin) ...[6, 7],
    ];
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      barrierColor: AppColors.ink.withValues(alpha: 0.46),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text(
                  'More tools',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              for (final index in indices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    selected: controller.selectedIndex == index,
                    selectedTileColor: AppColors.forestSoft,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    leading: Icon(
                      controller.selectedIndex == index
                          ? destinations[index].selectedIcon
                          : destinations[index].icon,
                      color: AppColors.forest,
                    ),
                    title: Text(
                      destinations[index].label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(destinations[index].subtitle),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(sheetContext, index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) controller.selectTab(selected);
  }

  Widget? _buildFloatingActionButton(BuildContext context) {
    if (controller.selectedIndex != 2) return null;
    return FloatingActionButton.extended(
      onPressed: controller.busy
          ? null
          : () => showMedicineFormSheet(context, controller),
      backgroundColor: AppColors.forest,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add medicine'),
    );
  }

  Future<void> _handleAction(BuildContext context, _AppAction action) async {
    if (!controller.isAdmin &&
        (action == _AppAction.loadSampleData ||
            action == _AppAction.clearData)) {
      _showMessage(context, 'Administrator access is required.', error: true);
      return;
    }
    switch (action) {
      case _AppAction.refresh:
        try {
          await controller.refresh();
          if (!context.mounted) return;
          _showMessage(context, 'MediStock is up to date.');
        } catch (_) {
          if (!context.mounted) return;
          _showMessage(
            context,
            'Could not refresh the local workspace.',
            error: true,
          );
        }
      case _AppAction.loadSampleData:
        try {
          final inserted = await controller.seedSampleData();
          if (!context.mounted) return;
          _showMessage(context, '$inserted sample medicines added.');
        } catch (_) {
          if (!context.mounted) return;
          _showMessage(
            context,
            'Could not load sample medicines.',
            error: true,
          );
        }
      case _AppAction.clearData:
        final shouldClear = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(
              Icons.delete_sweep_outlined,
              color: AppColors.danger,
            ),
            title: const Text('Clear local data?'),
            content: const Text(
              'This permanently removes medicines, invoices, and the current bill from this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Clear data'),
              ),
            ],
          ),
        );
        if (shouldClear != true || !context.mounted) return;
        try {
          await controller.clearAllData();
          if (!context.mounted) return;
          controller.selectTab(0);
          _showMessage(context, 'All local MediStock data was cleared.');
        } catch (_) {
          if (!context.mounted) return;
          _showMessage(context, 'Could not clear local data.', error: true);
        }
      case _AppAction.logout:
        final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.logout_rounded),
            title: const Text('Sign out?'),
            content: const Text(
              'Your medicines and invoices will remain safely stored on this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Stay signed in'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Sign out'),
              ),
            ],
          ),
        );
        if (shouldLogout == true) await controller.logout();
    }
  }

  void _showMessage(
    BuildContext context,
    String message, {
    bool error = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error ? AppColors.danger : AppColors.forestDark,
          content: Text(message),
        ),
      );
  }
}

class _WorkspaceBody extends StatefulWidget {
  const _WorkspaceBody({required this.controller});

  final AppController controller;

  @override
  State<_WorkspaceBody> createState() => _WorkspaceBodyState();
}

class _WorkspaceBodyState extends State<_WorkspaceBody> {
  List<Widget> _buildPages() {
    final controller = widget.controller;
    return <Widget>[
      DashboardScreen(
        key: const PageStorageKey<String>('overview'),
        controller: controller,
        onNavigate: (legacyIndex) {
          if (legacyIndex == 1) {
            controller.selectTab(2);
          } else {
            controller.selectSalesTab(1);
            controller.selectTab(3);
          }
        },
      ),
      PurchasesScreen(
        key: const PageStorageKey<String>('purchases'),
        controller: controller,
      ),
      InventoryScreen(
        key: const PageStorageKey<String>('stock'),
        controller: controller,
      ),
      SalesScreen(
        key: const PageStorageKey<String>('sales'),
        controller: controller,
      ),
      ReportsScreen(
        key: const PageStorageKey<String>('reports'),
        controller: controller,
      ),
      SupportScreen(
        key: const PageStorageKey<String>('support'),
        controller: controller,
      ),
      if (controller.isAdmin)
        BranchesScreen(
          key: const PageStorageKey<String>('branches'),
          controller: controller,
        ),
      if (controller.isAdmin)
        StaffScreen(
          key: const PageStorageKey<String>('staff'),
          controller: controller,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pages = _buildPages();
    return Column(
      children: [
        if (widget.controller.errorMessage != null)
          _ErrorNotice(
            message: 'A local operation could not be completed.',
            onDismiss: widget.controller.clearError,
          ),
        Expanded(
          child: AbsorbPointer(
            absorbing: widget.controller.busy,
            child: _StablePageStack(
              selectedIndex: widget.controller.selectedIndex,
              children: pages,
            ),
          ),
        ),
      ],
    );
  }
}

class _StablePageStack extends StatefulWidget {
  const _StablePageStack({required this.selectedIndex, required this.children});

  final int selectedIndex;
  final List<Widget> children;

  @override
  State<_StablePageStack> createState() => _StablePageStackState();
}

class _StablePageStackState extends State<_StablePageStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 170),
      value: 1,
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fade = Tween<double>(begin: 0.88, end: 1).animate(curved);
    _slide = Tween<Offset>(
      begin: const Offset(0.012, 0),
      end: Offset.zero,
    ).animate(curved);
  }

  @override
  void didUpdateWidget(covariant _StablePageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = IndexedStack(
      index: widget.selectedIndex,
      sizing: StackFit.expand,
      children: widget.children,
    );
    if (MediaQuery.disableAnimationsOf(context)) return page;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: page),
    );
  }
}

class _MobileCommandDock extends StatelessWidget {
  const _MobileCommandDock({
    required this.destinations,
    required this.selectedIndex,
    required this.enabled,
    required this.onSelected,
  });

  final List<_AppDestination> destinations;
  final int selectedIndex;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: EdgeInsets.fromLTRB(12, 4, 12, bottomInset > 0 ? 4 : 10),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(23),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.2),
              blurRadius: 22,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var index = 0; index < destinations.length; index++)
              Expanded(
                child: _DockButton(
                  destination: destinations[index],
                  selected: selectedIndex == index,
                  enabled: enabled,
                  onTap: () => onSelected(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.destination,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _AppDestination destination;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF78E0C5).withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 21,
                color: selected
                    ? const Color(0xFF78E0C5)
                    : const Color(0xFFB8C9C5),
              ),
              const SizedBox(height: 3),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFFB8C9C5),
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.destination,
    required this.busy,
    required this.isAdmin,
    required this.onRefresh,
    required this.onAction,
  });

  final _AppDestination destination;
  final bool busy;
  final bool isAdmin;
  final VoidCallback onRefresh;
  final ValueChanged<_AppAction> onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            border: Border(
              bottom: BorderSide(
                color: AppColors.muted.withValues(alpha: 0.12),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.label,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      destination.subtitle,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Refresh',
                onPressed: busy ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 8),
              _ActionMenu(
                enabled: !busy,
                isAdmin: isAdmin,
                onSelected: onAction,
              ),
            ],
          ),
        ),
        if (busy) const LinearProgressIndicator(minHeight: 3),
      ],
    );
  }
}

class _WideNavigation extends StatelessWidget {
  const _WideNavigation({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onAction,
    required this.isAdmin,
    required this.userName,
    required this.userSubtitle,
  });

  final List<_AppDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final ValueChanged<_AppAction> onAction;
  final bool isAdmin;
  final String userName;
  final String userSubtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 264,
      margin: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.forestDark, AppColors.forest],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestDark.withValues(alpha: 0.2),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 25, 20, 14),
            child: _SidebarBrand(),
          ),
          Expanded(
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              extended: true,
              scrollable: true,
              minExtendedWidth: 236,
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              groupAlignment: -0.72,
              indicatorColor: Colors.white.withValues(alpha: 0.16),
              selectedIconTheme: const IconThemeData(color: Colors.white),
              unselectedIconTheme: const IconThemeData(
                color: Color(0xFFB9DBD3),
              ),
              selectedLabelTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
              unselectedLabelTextStyle: const TextStyle(
                color: Color(0xFFD4E9E4),
                fontWeight: FontWeight.w600,
              ),
              destinations: [
                for (final item in destinations)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: Text(item.label),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.forestDark,
                    child: Icon(Icons.person_outline_rounded, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          userSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFFCAE4DE),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_AppAction>(
                    tooltip: 'Workspace actions',
                    color: Colors.white,
                    iconColor: Colors.white,
                    onSelected: onAction,
                    itemBuilder: (context) =>
                        _buildActionItems(context, isAdmin: isAdmin),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _CompactLogo(inverted: true),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MediStock',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              'PHARMACY WORKSPACE',
              style: TextStyle(
                color: Color(0xFFC9E4DE),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CompactLogo extends StatelessWidget {
  const _CompactLogo({this.inverted = false});

  final bool inverted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: inverted ? Colors.white : AppColors.forest,
        borderRadius: BorderRadius.circular(13),
        boxShadow: inverted
            ? null
            : [
                BoxShadow(
                  color: AppColors.forest.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
      ),
      child: Text(
        'Rx',
        style: TextStyle(
          color: inverted ? AppColors.forestDark : Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ActionMenu extends StatelessWidget {
  const _ActionMenu({
    required this.onSelected,
    required this.isAdmin,
    this.enabled = true,
  });

  final ValueChanged<_AppAction> onSelected;
  final bool isAdmin;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_AppAction>(
      tooltip: 'Workspace actions',
      enabled: enabled,
      onSelected: onSelected,
      itemBuilder: (context) => _buildActionItems(context, isAdmin: isAdmin),
    );
  }
}

List<PopupMenuEntry<_AppAction>> _buildActionItems(
  BuildContext context, {
  required bool isAdmin,
}) {
  return [
    if (isAdmin) ...const [
      PopupMenuItem(
        value: _AppAction.loadSampleData,
        child: _MenuLabel(
          icon: Icons.auto_awesome_outlined,
          label: 'Load sample data',
        ),
      ),
      PopupMenuItem(
        value: _AppAction.clearData,
        child: _MenuLabel(
          icon: Icons.delete_sweep_outlined,
          label: 'Clear local data',
        ),
      ),
      PopupMenuDivider(),
    ],
    const PopupMenuItem(
      value: _AppAction.logout,
      child: _MenuLabel(icon: Icons.logout_rounded, label: 'Sign out'),
    ),
  ];
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.danger.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.danger,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 19),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppDestination {
  const _AppDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.subtitle,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String subtitle;
}

enum _AppAction { refresh, loadSampleData, clearData, logout }
