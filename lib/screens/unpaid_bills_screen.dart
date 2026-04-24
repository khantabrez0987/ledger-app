import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';
import '../models/bill.dart';
import '../models/company.dart';
import '../models/ledger_mode.dart';
import '../models/ledger_transaction.dart';

class UnpaidBillsScreen extends StatefulWidget {
  final LedgerMode mode;

  const UnpaidBillsScreen({super.key, required this.mode});

  @override
  State<UnpaidBillsScreen> createState() => _UnpaidBillsScreenState();
}

class _UnpaidBillsScreenState extends State<UnpaidBillsScreen> {
  final db = DbHelper.instance;
  late Future<({
    List<MapEntry<Company, List<LedgerTransaction>>> transactions,
    List<MapEntry<Company, List<Bill>>> bills,
  })> _billsFuture;

  @override
  void initState() {
    super.initState();
    _loadUnpaidBills();
  }

  void _loadUnpaidBills() {
    _billsFuture = _fetchUnpaidBillsByCompany();
  }

  Future<({
    List<MapEntry<Company, List<LedgerTransaction>>> transactions,
    List<MapEntry<Company, List<Bill>>> bills,
  })> _fetchUnpaidBillsByCompany() async {
    final companies = await db.getCompanies(mode: widget.mode);
    final transactionResult = <MapEntry<Company, List<LedgerTransaction>>>[];
    final billResult = <MapEntry<Company, List<Bill>>>[];

    for (final company in companies) {
      // Fetch unpaid transactions with invoices
      final transactions =
          await db.getTransactions(company.name, mode: widget.mode);
      final unpaidWithInvoice = transactions
          .where((tx) => !tx.isCleared && tx.invoiceNumber.isNotEmpty)
          .toList();
      if (unpaidWithInvoice.isNotEmpty) {
        transactionResult.add(MapEntry(company, unpaidWithInvoice));
      }

      // Fetch unpaid and partially paid bills
      final unpaidBills = await db.getUnpaidBills(
        company.name,
        mode: widget.mode,
      );
      final partialBills = await db.getPartiallyPaidBills(
        company.name,
        mode: widget.mode,
      );
      final allUnpaidBills = [...unpaidBills, ...partialBills];
      if (allUnpaidBills.isNotEmpty) {
        billResult.add(MapEntry(company, allUnpaidBills));
      }
    }

    return (transactions: transactionResult, bills: billResult);
  }

  Future<void> _markAsPaid(
    String companyName,
    String invoiceNumber,
  ) async {
    await db.updateInvoiceClearStatus(
      companyName: companyName,
      invoiceNumber: invoiceNumber,
      isCleared: true,
      mode: widget.mode,
    );
    _loadUnpaidBills();
    setState(() {});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invoice marked as paid')),
    );
  }

  String _formatAmount(double value) {
    return NumberFormat.currency(symbol: '₹', decimalDigits: 2).format(value);
  }

  String _daysAgoLabel(DateTime date) {
    final today = DateTime.now();
    final difference = today.difference(date).inDays;
    if (difference <= 0) return 'Today';
    if (difference == 1) return '1 day ago';
    return '$difference days ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode == LedgerMode.sales
            ? 'Unpaid Sales Invoices'
            : 'Unpaid Purchase Invoices'),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF3F1EA), Color(0xFFE7E1D2)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: FutureBuilder<({
          List<MapEntry<Company, List<LedgerTransaction>>> transactions,
          List<MapEntry<Company, List<Bill>>> bills,
        })>(
          future: _billsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data;
            if (data == null) {
              return const Center(child: Text('Error loading bills'));
            }

            final billsByCompany = data.transactions;
            final billRecords = data.bills;
            final isEmpty = billsByCompany.isEmpty && billRecords.isEmpty;

            if (isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: Colors.green.shade300,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No unpaid bills!',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'All invoices and bills are paid.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              );
            }

            // Calculate total outstanding from both sources
            double totalUnpaid = 0;
            for (final entry in billsByCompany) {
              for (final tx in entry.value) {
                final isCredit =
                    tx.type == 'income' || tx.type == 'credit';
                if (isCredit) {
                  totalUnpaid += tx.amount;
                } else {
                  totalUnpaid -= tx.amount;
                }
              }
            }
            for (final entry in billRecords) {
              for (final bill in entry.value) {
                totalUnpaid += bill.remainingAmount;
              }
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Outstanding',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatAmount(totalUnpaid.abs()),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Display transaction-based invoices
                ...billsByCompany.map((entry) {
                  final company = entry.key;
                  final bills = entry.value;
                  final companyTotal = bills.fold<double>(0, (sum, tx) {
                    final isCredit = tx.type == 'income' || tx.type == 'credit';
                    return sum + (isCredit ? tx.amount : -tx.amount);
                  });

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              company.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Outstanding: ${_formatAmount(companyTotal.abs())}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...bills.map((bill) {
                        final isCredit =
                            bill.type == 'income' || bill.type == 'credit';
                        final amount = isCredit ? bill.amount : -bill.amount;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.orange.shade100,
                                  child: Icon(
                                    Icons.receipt,
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Invoice: ${bill.invoiceNumber}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${DateFormat('d MMM y').format(bill.date)} • ${_daysAgoLabel(bill.date)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      if (bill.note.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          bill.note,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _formatAmount(amount.abs()),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    FilledButton.icon(
                                      onPressed: () => _markAsPaid(
                                        company.name,
                                        bill.invoiceNumber,
                                      ),
                                      icon: const Icon(Icons.check, size: 16),
                                      label: const Text('Paid'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  );
                }).toList(),
                // Display new Bill records
                ...billRecords.map((entry) {
                  final company = entry.key;
                  final bills = entry.value;
                  final companyBillTotal =
                      bills.fold<double>(0, (sum, bill) => sum + bill.remainingAmount);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (billsByCompany.where((e) => e.key.name == company.name).isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                company.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Outstanding: ${_formatAmount(companyBillTotal)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ...bills.map((bill) {
                        final statusColor = bill.status == BillStatus.paid
                            ? Colors.green
                            : bill.status == BillStatus.partial
                                ? Colors.orange
                                : Colors.red;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: statusColor.withOpacity(0.2),
                                  child: Icon(
                                    Icons.inventory_2,
                                    color: statusColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Bill: ${bill.billId}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${DateFormat('d MMM y').format(bill.date)} • ${_daysAgoLabel(bill.date)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      LinearProgressIndicator(
                                        value: bill.percentagePaid / 100,
                                        minHeight: 6,
                                        backgroundColor: Colors.grey.shade300,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          statusColor,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Paid: ${bill.percentagePaid.toStringAsFixed(1)}% (₹${bill.paidAmount.toStringAsFixed(2)})',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Due: ${_formatAmount(bill.remainingAmount)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Total: ${_formatAmount(bill.totalAmount)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 16),
                    ],
                  );
                }).toList(),
              ],
            );
          },
        ),
      ),
    );
  }
}
