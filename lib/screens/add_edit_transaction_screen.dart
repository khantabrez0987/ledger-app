import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';
import '../models/ledger_mode.dart';
import '../models/ledger_transaction.dart';

class AddEditTransactionScreen extends StatefulWidget {
  final String companyName;
  final LedgerTransaction? transaction;
  final LedgerMode ledgerMode;

  const AddEditTransactionScreen({
    super.key,
    required this.companyName,
    required this.ledgerMode,
    this.transaction,
  });

  @override
  State<AddEditTransactionScreen> createState() =>
      _AddEditTransactionScreenState();
}

enum _TransactionSaveAction { saveNew, updateExisting }

class _AddEditTransactionScreenState extends State<AddEditTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  final _noteController = TextEditingController();
  final _paymentModeController = TextEditingController();
  final _invoiceNumberController = TextEditingController();
  final _dateController = TextEditingController();
  String _selectedType = 'credit';
  String? _selectedPaymentMode;
  DateTime _selectedDate = DateTime.now();
  bool _isCleared = false;
  bool _saving = false;
  final db = DbHelper.instance;
  static const List<String> _paymentModes = ['CASH', 'NEFT', 'RTGS', 'CHQ'];

  List<String> get _availablePaymentModes {
    final currentValue = _paymentModeController.text.trim();
    if (currentValue.isEmpty || _paymentModes.contains(currentValue)) {
      return _paymentModes;
    }
    return [currentValue, ..._paymentModes];
  }

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

  String _normalizeType(String type) {
    switch (type) {
      case 'income':
        return 'credit';
      case 'expense':
        return 'debit';
      default:
        return type;
    }
  }

  @override
  void initState() {
    super.initState();
    final tx = widget.transaction;
    if (tx != null) {
      _selectedType = _normalizeType(tx.type);
      _amountController.text = tx.amount.toStringAsFixed(2);
      _categoryController.text = tx.category;
      _noteController.text = tx.note;
      _paymentModeController.text = tx.paymentMode;
      _selectedPaymentMode =
          _paymentModes.contains(tx.paymentMode) ? tx.paymentMode : null;
      _invoiceNumberController.text = tx.invoiceNumber;
      _selectedDate = tx.date;
      _isCleared = tx.isCleared;
    } else {
      _categoryController.text = 'Yarn';
      _paymentModeController.text = 'CASH';
      _selectedPaymentMode = 'CASH';
    }
    _dateController.text = DateFormat.yMMMd().format(_selectedDate);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _categoryController.dispose();
    _noteController.dispose();
    _paymentModeController.dispose();
    _invoiceNumberController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat.yMMMd().format(_selectedDate);
      });
    }
  }

  DateTime? _parseDate(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final formats = [
      DateFormat.yMMMd(),
      DateFormat('yyyy-MM-dd'),
      DateFormat('dd/MM/yyyy'),
      DateFormat.yMd(),
    ];

    for (final format in formats) {
      try {
        return format.parseLoose(trimmed);
      } catch (_) {
        // ignore
      }
    }

    return DateTime.tryParse(trimmed);
  }

  Future<_TransactionSaveAction?> _showExistingTransactionDialog(
      LedgerTransaction existing) async {
    return showDialog<_TransactionSaveAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Existing transaction found'),
        content: Text(
          'A transaction with invoice number "${existing.invoiceNumber}" already exists. '
          'Do you want to update the existing transaction or save this as a new one?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_TransactionSaveAction.saveNew),
            child: const Text('Save as New'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context)
                .pop(_TransactionSaveAction.updateExisting),
            child: const Text('Update Existing'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final dateValue = _parseDate(_dateController.text.trim()) ?? _selectedDate;
    final transaction = LedgerTransaction(
      id: widget.transaction?.id,
      company: widget.companyName,
      ledgerMode: widget.ledgerMode,
      type: _selectedType,
      amount: amount,
      category: _categoryController.text.trim(),
      note: _noteController.text.trim(),
      paymentMode: _paymentModeController.text.trim(),
      fileNumber: widget.transaction?.fileNumber ?? '',
      invoiceNumber: _invoiceNumberController.text.trim(),
      isCleared: _isCleared,
      date: dateValue,
    );

    Future<void> syncInvoiceClearStatus(
        String invoiceNumber, bool isCleared) async {
      if (invoiceNumber.trim().isEmpty) {
        return;
      }
      await db.updateInvoiceClearStatus(
        companyName: widget.companyName,
        invoiceNumber: invoiceNumber,
        isCleared: isCleared,
        mode: widget.ledgerMode,
      );
    }

    if (widget.transaction == null && transaction.invoiceNumber.isNotEmpty) {
      final existing = await db.getTransactionByInvoiceNumber(
        widget.companyName,
        transaction.invoiceNumber,
        mode: widget.ledgerMode,
      );
      if (existing != null) {
        final action = await _showExistingTransactionDialog(existing);
        if (action == _TransactionSaveAction.updateExisting) {
          await db.updateTransaction(transaction.copyWith(id: existing.id));
          await syncInvoiceClearStatus(
              transaction.invoiceNumber, transaction.isCleared);
        } else if (action == _TransactionSaveAction.saveNew) {
          await db.addTransaction(transaction);
          await syncInvoiceClearStatus(
              transaction.invoiceNumber, transaction.isCleared);
        }
      } else {
        await db.addTransaction(transaction);
        await syncInvoiceClearStatus(
            transaction.invoiceNumber, transaction.isCleared);
      }
    } else if (widget.transaction == null) {
      await db.addTransaction(transaction);
      await syncInvoiceClearStatus(
          transaction.invoiceNumber, transaction.isCleared);
    } else {
      await db.updateTransaction(transaction);
      await syncInvoiceClearStatus(
          transaction.invoiceNumber, transaction.isCleared);
    }

    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.transaction != null;
    return Scaffold(
      appBar: AppBar(
          title: Text(isEditing ? 'Edit Transaction' : 'Add Transaction')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                items: const [
                  DropdownMenuItem(value: 'credit', child: Text('Credit')),
                  DropdownMenuItem(value: 'debit', child: Text('Debit')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedType = value;
                      if (_selectedType == 'debit') {
                        _selectedPaymentMode = null;
                        _paymentModeController.clear();
                      } else if (_paymentModeController.text.trim().isEmpty) {
                        _selectedPaymentMode = 'CASH';
                        _paymentModeController.text = 'CASH';
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter an amount.';
                  }
                  final parsed = double.tryParse(value.trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a valid positive number.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _invoiceNumberController,
                decoration: const InputDecoration(
                  labelText: 'Invoice Number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (_selectedType == 'credit') ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedPaymentMode,
                  items: _availablePaymentModes
                      .map(
                        (mode) =>
                            DropdownMenuItem(value: mode, child: Text(mode)),
                      )
                      .toList(),
                  decoration: const InputDecoration(
                    labelText: 'Payment Mode',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _selectedPaymentMode = value;
                      _paymentModeController.text = value ?? '';
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _dateController,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  labelText: 'Date',
                  border: const OutlineInputBorder(),
                  hintText: 'Apr 18, 2026 or 2026-04-18 or 18/04/2026',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_month),
                    onPressed: _pickDate,
                  ),
                ),
                validator: (value) {
                  final parsed = _parseDate(value ?? '');
                  if (parsed == null) {
                    return 'Enter a valid date.';
                  }
                  return null;
                },
                onChanged: (value) {
                  final parsed = _parseDate(value);
                  if (parsed != null) {
                    _selectedDate = parsed;
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Mark as cleared'),
                subtitle: const Text(
                    'Cleared transactions show red; pending ones show green.'),
                value: _isCleared,
                onChanged: (value) => setState(() => _isCleared = value),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notifications_active_outlined,
                        color: Colors.orange.shade800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Reminder: transaction date is ${_daysAgoLabel(_selectedDate)}',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _saveTransaction,
                child: _saving
                    ? const CircularProgressIndicator()
                    : Text(
                        isEditing ? 'Update Transaction' : 'Save Transaction'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
