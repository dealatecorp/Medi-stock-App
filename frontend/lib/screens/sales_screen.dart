import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../state/app_controller.dart';
import 'billing_screen.dart';
import 'invoices_screen.dart';

class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Semantics(
            label: 'Sales workspace view',
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.point_of_sale_outlined),
                  label: Text('New sale'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.receipt_long_outlined),
                  label: Text('History'),
                ),
              ],
              selected: {controller.selectedSalesTab},
              onSelectionChanged: (selection) {
                controller.selectSalesTab(selection.first);
              },
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.comfortable,
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  return states.contains(WidgetState.selected)
                      ? AppColors.forestSoft
                      : Colors.white;
                }),
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: controller.selectedSalesTab,
            sizing: StackFit.expand,
            children: [
              BillingScreen(controller: controller),
              InvoicesScreen(controller: controller),
            ],
          ),
        ),
      ],
    );
  }
}
