import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/ledger_transaction.dart';

class TransactionTile extends StatelessWidget {
  final LedgerTransaction transaction;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onTogglePaid;

  const TransactionTile({
    super.key,
    required this.transaction,
    required this.onEdit,
    required this.onDelete,
    this.onTogglePaid,
  });

  String _daysAgoLabel(DateTime date) {
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final difference = normalizedToday.difference(normalizedDate).inDays;

    if (difference <= 0) {
      return 'Today';
    }
    if (difference == 1) {
      return '1 day ago';
    }
    return '$difference days ago';
  }

  @override
  Widget build(BuildContext context) {
    final isCredit =
        transaction.type == 'credit' || transaction.type == 'income';
    final amountLabel = NumberFormat.currency(symbol: '₹', decimalDigits: 2)
        .format(transaction.amount);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      color: transaction.isCleared ? Colors.grey.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: transaction.isCleared
                  ? Colors.grey.shade300
                  : (isCredit ? Colors.green.shade100 : Colors.red.shade100),
              child: Icon(
                transaction.isCleared
                    ? Icons.check_circle
                    : (isCredit ? Icons.arrow_upward : Icons.arrow_downward),
                color: transaction.isCleared
                    ? Colors.green
                    : (isCredit ? Colors.green : Colors.red),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.category.isEmpty
                        ? 'No category'
                        : transaction.category,
                    style: TextStyle(
                      decoration: transaction.isCleared
                          ? TextDecoration.lineThrough
                          : null,
                      color: transaction.isCleared ? Colors.grey : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (transaction.paymentMode.isNotEmpty)
                    Text(
                      'Payment Mode: ${transaction.paymentMode}',
                      style: TextStyle(
                        color: transaction.isCleared ? Colors.grey : null,
                      ),
                    ),
                  if (transaction.invoiceNumber.isNotEmpty)
                    Text(
                      'Invoice: ${transaction.invoiceNumber}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: transaction.isCleared ? Colors.grey : null,
                      ),
                    ),
                  if (transaction.note.isNotEmpty)
                    Text(
                      transaction.note,
                      style: TextStyle(
                        color: transaction.isCleared ? Colors.grey : null,
                      ),
                    ),
                  if (transaction.note.isEmpty)
                    Text(
                      'No note',
                      style: TextStyle(
                        color: transaction.isCleared ? Colors.grey : null,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat.yMMMd().format(transaction.date),
                    style: TextStyle(
                      color: transaction.isCleared ? Colors.grey : null,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        'Reminder: ${_daysAgoLabel(transaction.date)}',
                        style: TextStyle(
                          color: transaction.isCleared
                              ? Colors.grey
                              : Colors.orange.shade800,
                        ),
                      ),
                      if (transaction.isCleared) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Paid',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isCredit ? '+' : '-'}$amountLabel',
                  style: TextStyle(
                    color: transaction.isCleared
                        ? Colors.grey
                        : (isCredit
                            ? Colors.green.shade700
                            : Colors.red.shade700),
                    fontWeight: FontWeight.bold,
                    decoration: transaction.isCleared
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onTogglePaid != null && transaction.invoiceNumber.isNotEmpty)
                      IconButton(
                        icon: Icon(
                          transaction.isCleared
                              ? Icons.payment
                              : Icons.check_box_outline_blank,
                          size: 20,
                          color: transaction.isCleared
                              ? Colors.green
                              : Colors.grey,
                        ),
                        tooltip: transaction.isCleared
                            ? 'Mark as unpaid'
                            : 'Mark as paid',
                        visualDensity: VisualDensity.compact,
                        onPressed: onTogglePaid,
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      tooltip: 'Edit',
                      visualDensity: VisualDensity.compact,
                      onPressed: onEdit,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20),
                      tooltip: 'Delete',
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
