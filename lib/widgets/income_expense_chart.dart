import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class IncomeExpenseChart extends StatelessWidget {
  final double income;
  final double expense;

  const IncomeExpenseChart({super.key, required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    final double maxValue = (income > expense ? income : expense)
        .clamp(1.0, double.infinity);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Credit vs Debit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildBar('Income', income, maxValue, Colors.green)),
              const SizedBox(width: 16),
              Expanded(child: _buildBar('Expense', expense, maxValue, Colors.red)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBar(String label, double amount, double maxValue, Color color) {
    final formatter = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
    final height = amount / maxValue * 120;
    return Column(
      children: [
        Container(
          height: 120,
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            height: height,
            width: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label),
        const SizedBox(height: 4),
        Text(formatter.format(amount), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
