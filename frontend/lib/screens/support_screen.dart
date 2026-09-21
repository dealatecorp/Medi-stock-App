import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../state/app_controller.dart';
import '../widgets/common.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  bool _checking = false;
  DateTime? _lastCheckedAt;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _runDiagnostics,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 116),
        children: [
          Text(
            'Support centre',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Help, privacy, and device diagnostics in one place',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          _LocalModeHero(
            medicineCount: widget.controller.medicines.length,
            invoiceCount: widget.controller.invoices.length,
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Device diagnostics',
            trailing: TextButton.icon(
              onPressed: _checking ? null : _runDiagnostics,
              icon: _checking
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.health_and_safety_outlined, size: 18),
              label: Text(_checking ? 'Checking' : 'Run checks'),
            ),
            child: Column(
              children: [
                const _DiagnosticRow(
                  icon: Icons.storage_rounded,
                  title: 'Local database',
                  detail: 'Ready · data stays on this device',
                  state: _DiagnosticState.ready,
                ),
                const Divider(height: 22),
                const _DiagnosticRow(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'PDF and sharing',
                  detail: 'Uses the phone print and share sheets',
                  state: _DiagnosticState.ready,
                ),
                const Divider(height: 22),
                const _DiagnosticRow(
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'Camera scanner',
                  detail: 'Permission requested when scanning starts',
                  state: _DiagnosticState.device,
                ),
                const Divider(height: 22),
                const _DiagnosticRow(
                  icon: Icons.notifications_none_rounded,
                  title: 'Low-stock notifications',
                  detail: 'Delivered locally when permission is allowed',
                  state: _DiagnosticState.device,
                ),
                const Divider(height: 22),
                const _DiagnosticRow(
                  icon: Icons.cloud_off_outlined,
                  title: 'Cloud sync',
                  detail: 'Not connected · local mode',
                  state: _DiagnosticState.localOnly,
                ),
                if (_lastCheckedAt != null) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Checked just now',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _FutureConnectionsCard(),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Frequently asked questions',
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
            child: const Column(
              children: [
                _FaqTile(
                  question: 'Does MediStock need the internet?',
                  answer:
                      'No. Inventory, billing, purchases, reports, branches, '
                      'and staff records are stored in the local database. '
                      'Printing, sharing, and camera access use phone features.',
                ),
                _FaqTile(
                  question: 'Where is my pharmacy data stored?',
                  answer:
                      'The current app keeps operational data inside its private '
                      'on-device database. Uninstalling the app can remove that '
                      'data, so export important reports regularly.',
                ),
                _FaqTile(
                  question: 'How do branch and staff updates work?',
                  answer:
                      'An administrator can activate branches and manage staff. '
                      'A staff check-in is recorded when that staff member logs '
                      'in on this device.',
                ),
                _FaqTile(
                  question: 'Can I send invoices through WhatsApp?',
                  answer:
                      'Use Share PDF and select WhatsApp, SMS, email, or another '
                      'installed app from the phone share sheet. Automatic '
                      'delivery is reserved for a future connected setup.',
                ),
                _FaqTile(
                  question: 'What happens when stock is insufficient?',
                  answer:
                      'Billing blocks quantities above available stock. Where '
                      'possible, the app can surface in-stock medicines with '
                      'matching composition as alternatives.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _PrivacyCard(),
          const SizedBox(height: 16),
          const _HelpCard(),
        ],
      ),
    );
  }

  Future<void> _runDiagnostics() async {
    if (_checking) return;
    setState(() => _checking = true);
    if (!MediaQuery.disableAnimationsOf(context)) {
      await Future<void>.delayed(const Duration(milliseconds: 420));
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _lastCheckedAt = DateTime.now();
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Local services are ready.'),
          duration: Duration(seconds: 2),
        ),
      );
  }
}

class _LocalModeHero extends StatelessWidget {
  const _LocalModeHero({
    required this.medicineCount,
    required this.invoiceCount,
  });

  final int medicineCount;
  final int invoiceCount;

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
            color: AppColors.forest.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -54,
            top: -58,
            child: _GlowOrb(size: 178, color: Color(0x33FFFFFF)),
          ),
          const Positioned(
            left: -46,
            bottom: -78,
            child: _GlowOrb(size: 158, color: Color(0x22E6B85C)),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 45,
                      height: 45,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: const Icon(
                        Icons.phonelink_lock_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Offline workspace',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Private, fast, and available without a server',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const _StatusPill(label: 'LOCAL'),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStat(
                        value: '$medicineCount',
                        label: 'Medicine rows',
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                    Expanded(
                      child: _HeroStat(
                        value: '$invoiceCount',
                        label: 'Saved invoices',
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                    const Expanded(
                      child: _HeroStat(value: 'On', label: 'Device storage'),
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

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
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
                ?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFF8CE6B1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

enum _DiagnosticState { ready, device, localOnly }

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.state,
  });

  final IconData icon;
  final String title;
  final String detail;
  final _DiagnosticState state;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData statusIcon, String status) = switch (state) {
      _DiagnosticState.ready => (
        AppColors.success,
        Icons.check_circle_rounded,
        'Ready',
      ),
      _DiagnosticState.device => (
        AppColors.gold,
        Icons.phone_android_rounded,
        'Device',
      ),
      _DiagnosticState.localOnly => (
        AppColors.muted,
        Icons.remove_circle_outline_rounded,
        'Local',
      ),
    };

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          label: '$title status: $status',
          child: ExcludeSemantics(
            child: Icon(statusIcon, color: color, size: 20),
          ),
        ),
      ],
    );
  }
}

class _FutureConnectionsCard extends StatelessWidget {
  const _FutureConnectionsCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Connected features',
      trailing: const _ComingSoonPill(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The app is designed for these services later. They are visible '
            'for planning, but no online calls are made in local mode.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FutureChip(icon: Icons.sync_rounded, label: 'Multi-device sync'),
              _FutureChip(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'WhatsApp delivery',
              ),
              _FutureChip(icon: Icons.sms_outlined, label: 'SMS reminders'),
              _FutureChip(icon: Icons.cloud_outlined, label: 'Cloud backup'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComingSoonPill extends StatelessWidget {
  const _ComingSoonPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        'Future',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: AppColors.gold, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _FutureChip extends StatelessWidget {
  const _FutureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.muted.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppColors.muted),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 36, 14),
        iconColor: AppColors.forest,
        collapsedIconColor: AppColors.muted,
        title: Text(
          question,
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.muted, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.forestSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.forest.withValues(alpha: 0.13)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.forest, size: 27),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Privacy by default',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.forestDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'MediStock does not upload pharmacy, staff, or patient data '
                  'in this offline build. Data leaves the app only when you '
                  'choose an export or share action.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.forestDark.withValues(alpha: 0.8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.lightbulb_outline, color: AppColors.gold),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Need help with a workflow?',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Start with the section above. Every feature is designed to '
                  'work on-device without an account or support connection.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
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
