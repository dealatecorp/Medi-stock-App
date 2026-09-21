import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:medistock_backend/medistock_backend.dart';

import '../core/app_theme.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  List<StaffMember> get _filteredStaff {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.controller.staffMembers.toList();
    return widget.controller.staffMembers
        .where((member) {
          return member.name.toLowerCase().contains(query) ||
              member.email.toLowerCase().contains(query) ||
              member.role.toLowerCase().contains(query) ||
              member.branch.toLowerCase().contains(query) ||
              'shift ${member.shift}'.toLowerCase().contains(query);
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
    final staff = widget.controller.staffMembers;
    final activeCount = staff.where((member) => member.isActive).length;
    final checkedInCount = staff
        .where((member) => member.checkedInToday)
        .length;
    final filteredStaff = _filteredStaff;

    return RefreshIndicator(
      onRefresh: widget.controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 116),
        children: [
          _PageHeading(onAdd: () => _openStaffForm()),
          const SizedBox(height: 18),
          _OverviewStrip(
            total: staff.length,
            active: activeCount,
            checkedIn: checkedInCount,
          ),
          const SizedBox(height: 16),
          _SearchBox(
            controller: _searchController,
            resultCount: filteredStaff.length,
            onChanged: (value) => setState(() => _query = value),
            onClear: () {
              _searchController.clear();
              setState(() => _query = '');
            },
          ),
          const SizedBox(height: 16),
          if (filteredStaff.isEmpty)
            SectionCard(
              child: EmptyState(
                icon: _query.isEmpty
                    ? Icons.groups_2_outlined
                    : Icons.manage_search_rounded,
                title: _query.isEmpty ? 'No staff added yet' : 'No staff found',
                message: _query.isEmpty
                    ? 'Add a staff member to start monitoring branch attendance.'
                    : 'Try a different name, email, role, or branch.',
                action: _query.isEmpty
                    ? FilledButton.icon(
                        onPressed: () => _openStaffForm(),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Add staff'),
                      )
                    : TextButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        child: const Text('Clear search'),
                      ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1120
                    ? 3
                    : constraints.maxWidth >= 700
                    ? 2
                    : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredStaff.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    mainAxisExtent: 308,
                  ),
                  itemBuilder: (context, index) {
                    final member = filteredStaff[index];
                    return _StaffCard(
                      member: member,
                      onEdit: () => _openStaffForm(member),
                      onDelete: () => _confirmDelete(member),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _openStaffForm([StaffMember? member]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _StaffFormSheet(controller: widget.controller, member: member),
    );
    if (saved != true || !mounted) return;
    _showMessage(member == null ? 'Staff member added.' : 'Staff updated.');
  }

  Future<void> _confirmDelete(StaffMember member) async {
    final id = member.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.person_remove_outlined, color: AppColors.danger),
        title: const Text('Remove staff member?'),
        content: Text(
          '${member.name} will lose access to MediStock. Existing login activity remains in the local audit history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.deleteStaff(id);
      if (!mounted) return;
      _showMessage('${member.name} was removed.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not remove ${member.name}.', error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
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

class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Staff monitoring',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.45,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Manage access and see who checked in today.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.muted),
            ),
          ],
        );
        final action = FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Add staff'),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [heading, const SizedBox(height: 14), action],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            action,
          ],
        );
      },
    );
  }
}

class _OverviewStrip extends StatelessWidget {
  const _OverviewStrip({
    required this.total,
    required this.active,
    required this.checkedIn,
  });

  final int total;
  final int active;
  final int checkedIn;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 480;
        final items = <Widget>[
          _OverviewTile(
            label: 'Total staff',
            shortLabel: 'Staff',
            value: '$total',
            icon: Icons.groups_2_outlined,
            color: AppColors.forest,
          ),
          _OverviewTile(
            label: 'Active access',
            shortLabel: 'Active',
            value: '$active',
            icon: Icons.verified_user_outlined,
            color: AppColors.gold,
          ),
          _OverviewTile(
            label: 'Checked in today',
            shortLabel: 'Here today',
            value: '$checkedIn',
            icon: Icons.how_to_reg_rounded,
            color: AppColors.success,
          ),
        ];

        return SizedBox(
          height: compact ? 116 : 128,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < items.length; index++) ...[
                Expanded(
                  child: _OverviewTileScope(
                    compact: compact,
                    child: items[index],
                  ),
                ),
                if (index < items.length - 1) const SizedBox(width: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _OverviewTileScope extends InheritedWidget {
  const _OverviewTileScope({required this.compact, required super.child});

  final bool compact;

  static bool compactOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_OverviewTileScope>()
          ?.compact ??
      false;

  @override
  bool updateShouldNotify(_OverviewTileScope oldWidget) =>
      compact != oldWidget.compact;
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.label,
    required this.shortLabel,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String shortLabel;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final compact = _OverviewTileScope.compactOf(context);
    return Container(
      padding: EdgeInsets.all(compact ? 11 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(compact ? 7 : 9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: compact ? 18 : 21),
              ),
              const Spacer(),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            compact ? shortLabel : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.resultCount,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final int resultCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search name, email, role, or branch',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: onClear,
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.forestSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$resultCount',
              semanticsLabel: '$resultCount results',
              style: const TextStyle(
                color: AppColors.forestDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.member,
    required this.onEdit,
    required this.onDelete,
  });

  final StaffMember member;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final initials = member.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return _SpotlightSurface(
      semanticsLabel:
          '${member.name}, ${member.role}, ${member.branch}, shift ${member.shift}, ${staffShiftHours[member.shift]}, ${member.isActive ? 'active' : 'inactive'}',
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.forest, AppColors.forestDark],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.forest.withValues(alpha: 0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        member.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _AccessBadge(active: member.isActive),
              ],
            ),
            const SizedBox(height: 17),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoPill(icon: Icons.badge_outlined, label: member.role),
                _InfoPill(
                  icon: Icons.store_mall_directory_outlined,
                  label: member.branch,
                ),
                _InfoPill(
                  icon: Icons.schedule_rounded,
                  label: 'Shift ${member.shift}: ${staffShiftHours[member.shift]}',
                ),
              ],
            ),
            const Spacer(),
            Divider(color: AppColors.muted.withValues(alpha: 0.13)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LAST LOGIN',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatLastLogin(member.lastLoginAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (member.checkedInToday)
                  _TodayBadge(loginCount: member.todayLoginCount),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 9),
                IconButton.outlined(
                  tooltip: 'Remove ${member.name}',
                  onPressed: onDelete,
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(
                      color: AppColors.danger.withValues(alpha: 0.28),
                    ),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightSurface extends StatefulWidget {
  const _SpotlightSurface({required this.child, required this.semanticsLabel});

  final Widget child;
  final String semanticsLabel;

  @override
  State<_SpotlightSurface> createState() => _SpotlightSurfaceState();
}

class _SpotlightSurfaceState extends State<_SpotlightSurface> {
  bool _hovered = false;
  Offset _spot = const Offset(110, 80);

  void _updateSpot(PointerHoverEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    setState(() => _spot = box.globalToLocal(event.position));
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        onHover: _updateSpot,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _hovered
                  ? AppColors.forest.withValues(alpha: 0.42)
                  : AppColors.gold.withValues(alpha: 0.18),
              width: _hovered ? 1.25 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.forest.withValues(
                  alpha: _hovered ? 0.14 : 0.055,
                ),
                blurRadius: _hovered ? 28 : 18,
                offset: Offset(0, _hovered ? 12 : 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                left: _spot.dx - 120,
                top: _spot.dy - 120,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _hovered ? 1 : 0,
                    duration: duration,
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            AppColors.forest.withValues(alpha: 0.11),
                            AppColors.forest.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -35,
                top: -42,
                child: IgnorePointer(
                  child: Container(
                    width: 122,
                    height: 122,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.gold.withValues(alpha: 0.09),
                          AppColors.gold.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccessBadge extends StatelessWidget {
  const _AccessBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : AppColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.forestSoft.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.forestDark, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.forestDark,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayBadge extends StatelessWidget {
  const _TodayBadge({required this.loginCount});

  final int loginCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Checked in today, $loginCount login${loginCount == 1 ? '' : 's'}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.success.withValues(alpha: 0.16),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LiveDot(),
              SizedBox(width: 6),
              Text(
                'Here today',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      lowerBound: 0.72,
      upperBound: 1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const _DotBody(scale: 1);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => _DotBody(scale: _controller.value),
    );
  }
}

class _DotBody extends StatelessWidget {
  const _DotBody({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: AppColors.success,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _StaffFormSheet extends StatefulWidget {
  const _StaffFormSheet({required this.controller, this.member});

  final AppController controller;
  final StaffMember? member;

  @override
  State<_StaffFormSheet> createState() => _StaffFormSheetState();
}

class _StaffFormSheetState extends State<_StaffFormSheet> {
  static const _roles = <String>[
    'Branch Manager',
    'Pharmacist',
    'Inventory Manager',
    'Cashier',
    'Pharmacy Assistant',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _pinController;
  late String _role;
  late String _branch;
  late String _shift;
  late bool _active;
  bool _saving = false;
  bool _obscurePin = true;

  bool get _editing => widget.member != null;

  List<String> get _roleOptions {
    final current = widget.member?.role;
    if (current == null || current.isEmpty || _roles.contains(current)) {
      return _roles;
    }
    return [current, ..._roles];
  }

  List<String> get _branchOptions {
    final current = widget.member?.branch;
    if (current == null ||
        current.isEmpty ||
        medistockBranches.contains(current)) {
      return medistockBranches;
    }
    return [current, ...medistockBranches];
  }

  @override
  void initState() {
    super.initState();
    final member = widget.member;
    _nameController = TextEditingController(text: member?.name ?? '');
    _emailController = TextEditingController(text: member?.email ?? '');
    _pinController = TextEditingController();
    _role = member?.role ?? _roles.first;
    _branch = member?.branch ?? medistockBranches.first;
    _shift = member?.shift ?? staffShifts.first;
    _active = member?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: screenHeight * 0.94,
          ),
          child: Material(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.muted.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: AppColors.forestSoft,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.manage_accounts_outlined,
                                  color: AppColors.forest,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _editing ? 'Edit staff' : 'Add staff',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            color: AppColors.ink,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _editing
                                          ? 'Update access, role, or branch assignment.'
                                          : 'Create secure access for a branch team member.',
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                onPressed: _saving
                                    ? null
                                    : () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (value) {
                              final name = value?.trim() ?? '';
                              if (name.isEmpty) return 'Enter the staff name.';
                              if (name.length < 2) {
                                return 'Name must have at least 2 characters.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 13),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email address',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              if (email.isEmpty) {
                                return 'Enter an email address.';
                              }
                              final valid = RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(email);
                              return valid
                                  ? null
                                  : 'Enter a valid email address.';
                            },
                          ),
                          const SizedBox(height: 13),
                          TextFormField(
                            controller: _pinController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            obscureText: _obscurePin,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(8),
                            ],
                            decoration: InputDecoration(
                              labelText: _editing
                                  ? 'New PIN (optional)'
                                  : 'Login PIN',
                              helperText: _editing
                                  ? 'Leave blank to keep the existing PIN.'
                                  : 'Use 4 to 8 digits.',
                              prefixIcon: const Icon(Icons.pin_outlined),
                              suffixIcon: IconButton(
                                tooltip: _obscurePin ? 'Show PIN' : 'Hide PIN',
                                onPressed: () =>
                                    setState(() => _obscurePin = !_obscurePin),
                                icon: Icon(
                                  _obscurePin
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) {
                              final pin = value?.trim() ?? '';
                              if (!_editing && pin.isEmpty) {
                                return 'Create a login PIN.';
                              }
                              if (pin.isNotEmpty && pin.length < 4) {
                                return 'PIN must contain at least 4 digits.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 13),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final roleField = DropdownButtonFormField<String>(
                                initialValue: _role,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Role',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                items: _roleOptions
                                    .map(
                                      (role) => DropdownMenuItem(
                                        value: role,
                                        child: Text(
                                          role,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: _saving
                                    ? null
                                    : (value) {
                                        if (value != null) _role = value;
                                      },
                              );
                              final branchField =
                                  DropdownButtonFormField<String>(
                                    initialValue: _branch,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Branch',
                                      prefixIcon: Icon(
                                        Icons.store_mall_directory_outlined,
                                      ),
                                    ),
                                    items: _branchOptions
                                        .map(
                                          (branch) => DropdownMenuItem(
                                            value: branch,
                                            child: Text(
                                              branch,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: _saving
                                        ? null
                                        : (value) {
                                            if (value != null) _branch = value;
                                          },
                                  );

                              if (constraints.maxWidth < 520) {
                                return Column(
                                  children: [
                                    roleField,
                                    const SizedBox(height: 13),
                                    branchField,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: roleField),
                                  const SizedBox(width: 12),
                                  Expanded(child: branchField),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _shift,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Work shift',
                              prefixIcon: Icon(Icons.schedule_rounded),
                            ),
                            items: staffShifts
                                .map(
                                  (shift) => DropdownMenuItem(
                                    value: shift,
                                    child: Text(
                                      'Shift $shift: ${staffShiftHours[shift]}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value != null) _shift = value;
                                  },
                          ),
                          const SizedBox(height: 14),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.forestSoft.withValues(
                                alpha: 0.55,
                              ),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: AppColors.forest.withValues(alpha: 0.1),
                              ),
                            ),
                            child: SwitchListTile.adaptive(
                              value: _active,
                              onChanged: _saving
                                  ? null
                                  : (value) => setState(() => _active = value),
                              title: const Text(
                                'Active access',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: const Text(
                                'Allow this staff member to sign in.',
                              ),
                              secondary: const Icon(
                                Icons.verified_user_outlined,
                                color: AppColors.forest,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    _editing
                                        ? Icons.save_outlined
                                        : Icons.person_add_alt_1_rounded,
                                  ),
                            label: Text(
                              _saving
                                  ? 'Saving…'
                                  : _editing
                                  ? 'Save changes'
                                  : 'Add staff member',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final previous = widget.member;
    final member = StaffMember(
      id: previous?.id,
      name: _nameController.text.trim(),
      email: _emailController.text.trim().toLowerCase(),
      role: _role,
      branch: _branch,
      shift: _shift,
      isActive: _active,
      lastLoginAt: previous?.lastLoginAt,
      todayLoginCount: previous?.todayLoginCount ?? 0,
      createdAt: previous?.createdAt,
      updatedAt: previous?.updatedAt,
    );
    final pin = _pinController.text.trim();
    try {
      await widget.controller.saveStaff(member, pin: pin.isEmpty ? null : pin);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text(_friendlyError(error)),
          ),
        );
    }
  }
}

String _formatLastLogin(DateTime? value) {
  if (value == null) return 'Never signed in';
  final local = value.toLocal();
  final now = DateTime.now();
  final isToday =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (isToday) return 'Today, ${DateFormat.jm().format(local)}';
  return DateFormat('d MMM y, h:mm a').format(local);
}

String _friendlyError(Object error) {
  final message = error.toString().replaceFirst(
    RegExp(r'^\w+Exception:\s*'),
    '',
  );
  if (message.toLowerCase().contains('unique') ||
      message.toLowerCase().contains('email')) {
    return 'That email address is already in use.';
  }
  return message.isEmpty ? 'Could not save this staff member.' : message;
}
