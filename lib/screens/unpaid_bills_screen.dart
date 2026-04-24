import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';
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
  late Future<List<MapEntry<Company, List<LedgerTransaction>>>> _billsFuture;

  @override
  void initState() {
    super.initState();
    _loadUnpaidBills();
  }

  void _loadUnpaidBills() {
    _billsFuture = _fetchUnpaidBillsByCompany();
  }

  Future<List<MapEntry<Company, List<LedgerTransaction>>>>
      _fetchUnpaidBillsByCompany() async {
    final companies = await db.getCompanies(mode: widget.mode);
    final result = <MapEntry<Company, List<LedgerTransaction>>>[];

    for (final company in companies) {
      final transactions =
          await db.getTransactions(company.name, mode: widget.mode);
      final unpaidWithInvoice = transactions
          .where((tx) => !tx.isCleared && tx.invoiceNumber.isNotEmpty)
          .toList();

      if (unpaidWithInvoice.isNotEmpty) {
        result.add(MapEntry(company, unpaidWithInvoice));
      }
    }

    return result;
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
        child: FutureBuilder<List<MapEntry<Company, List<LedgerTransaction>>>>(
          future: _billsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final billsByCompany = snapshot.data ?? [];

            if (billsByCompany.isEmpty) {
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
                      'All invoices are paid.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              );
            }

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
