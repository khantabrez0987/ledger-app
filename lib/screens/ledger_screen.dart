import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../db_helper.dart';
import '../models/company.dart';
import '../models/ledger_mode.dart';
import '../models/ledger_transaction.dart';
import '../widgets/company_logo.dart';
import 'add_edit_transaction_screen.dart';

class LedgerScreen extends StatefulWidget {
  final Company company;
  final LedgerMode mode;

  const LedgerScreen({super.key, required this.company, required this.mode});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class AddTransactionIntent extends Intent {
  const AddTransactionIntent();
}

class _LedgerScreenState extends State<LedgerScreen> {
  static const MethodChannel _whatsappChannel =
      MethodChannel('ledger_app/whatsapp_share');
  final db = DbHelper.instance;
  final _searchController = TextEditingController();
  late Future<List<LedgerTransaction>> _transactionsFuture;
  String _searchQuery = '';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  void _loadTransactions() {
    _transactionsFuture = db.getTransactions(
      widget.company.name,
      searchQuery: _searchQuery,
      from: _fromDate,
      to: _toDate,
      mode: widget.mode,
    );
  }

  void _refresh() {
    setState(_loadTransactions);
  }

  void _clearSearch() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _loadTransactions();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showAddTransaction([LedgerTransaction? transaction]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEditTransactionScreen(
          companyName: widget.company.name,
          ledgerMode: widget.mode,
          transaction: transaction,
        ),
      ),
    );
    if (saved == true) {
      _refresh();
    }
  }

  Future<void> _deleteTransaction(int id) async {
    await db.deleteTransaction(id);
    _refresh();
  }

  Future<void> _confirmDeleteTransaction(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content:
              const Text('Are you sure you want to delete this transaction?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteTransaction(id);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 30)),
              end: DateTime.now(),
            ),
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      _refresh();
    }
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _fromDate = null;
      _toDate = null;
    });
    _refresh();
  }

  Future<void> _toggleInvoicePaymentStatus(
    String invoiceNumber,
    bool isCurrentlyCleared,
  ) async {
    if (invoiceNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This transaction has no invoice number')),
      );
      return;
    }

    await db.updateInvoiceClearStatus(
      companyName: widget.company.name,
      invoiceNumber: invoiceNumber,
      isCleared: !isCurrentlyCleared,
      mode: widget.mode,
    );
    _refresh();
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isCurrentlyCleared ? 'Marked as unpaid' : 'Marked as paid',
        ),
      ),
    );
  }

  bool _isCredit(LedgerTransaction tx) {
    return tx.type == 'income' || tx.type == 'credit';
  }

  String _typeLabel(LedgerTransaction tx) {
    if (_isCredit(tx)) {
      return 'Receipt';
    }
    return widget.mode == LedgerMode.purchase ? 'Purchase' : 'Sales';
  }

  String _accountLabel(LedgerTransaction tx) {
    final parts = <String>[
      if (tx.category.isNotEmpty) tx.category,
      if (tx.paymentMode.isNotEmpty) tx.paymentMode,
      if (tx.note.isNotEmpty) tx.note,
    ];
    return parts.isEmpty ? '-' : parts.join(' / ');
  }

  String _formatAmount(double value) {
    return NumberFormat.currency(symbol: '', decimalDigits: 2)
        .format(value)
        .trim();
  }

  String _formatBalance(double value) {
    final label = _formatAmount(value.abs());
    if (value == 0) {
      return '$label Dr';
    }
    return value >= 0 ? '$label Cr' : '$label Dr';
  }

  String _dateRangeLabel() {
    final formatter = DateFormat('d-M-yyyy');
    final from = _fromDate;
    final to = _toDate;
    if (from == null && to == null) {
      return 'All transactions';
    }
    if (from != null && to != null) {
      return 'From ${formatter.format(from)} to ${formatter.format(to)}';
    }
    if (from != null) {
      return 'From ${formatter.format(from)}';
    }
    return 'Until ${formatter.format(to!)}';
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

  List<LedgerTransaction> _sortedTransactions(
      List<LedgerTransaction> transactions) {
    return [...transactions]..sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) {
          return dateCompare;
        }
        return (a.id ?? 0).compareTo(b.id ?? 0);
      });
  }

  Future<List<LedgerTransaction>> _loadCurrentTransactions() {
    return db.getTransactions(
      widget.company.name,
      searchQuery: _searchQuery,
      from: _fromDate,
      to: _toDate,
      mode: widget.mode,
    );
  }

  String _pdfFileName() {
    final sanitizedName =
        widget.company.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return '${sanitizedName}_ledger.pdf';
  }

  Future<Uint8List> _buildLedgerPdf(
      List<LedgerTransaction> transactions) async {
    final pdf = pw.Document();
    final logoBytes = await rootBundle.load(CompanyLogo.pdfAssetPath);
    final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    final sortedTransactions = _sortedTransactions(transactions);
    final totalCredit = sortedTransactions
        .where(_isCredit)
        .fold<double>(0, (sum, tx) => sum + tx.amount);
    final totalDebit = sortedTransactions
        .where((tx) => !_isCredit(tx))
        .fold<double>(0, (sum, tx) => sum + tx.amount);

    double runningBalance = 0;
    final rows = sortedTransactions.map((tx) {
      final credit = _isCredit(tx) ? tx.amount : 0.0;
      final debit = _isCredit(tx) ? 0.0 : tx.amount;
      if (!tx.isCleared) {
        runningBalance += credit - debit;
      }
      return <String>[
        DateFormat('dd-MM-yyyy').format(tx.date),
        _daysAgoLabel(tx.date),
        _typeLabel(tx),
        tx.invoiceNumber,
        _accountLabel(tx),
        debit == 0 ? '-' : _formatAmount(debit),
        credit == 0 ? '-' : _formatAmount(credit),
        _formatBalance(runningBalance),
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Center(
            child: pw.Image(
              logoImage,
              height: 72,
              fit: pw.BoxFit.contain,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            widget.company.name.toUpperCase(),
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Account Ledger', style: const pw.TextStyle(fontSize: 14)),
          if (widget.company.address.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text('Address: ${widget.company.address}'),
          ],
          if (widget.company.mobileNumber.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text('Mobile: ${widget.company.mobileNumber}'),
          ],
          pw.SizedBox(height: 2),
          pw.Text(_dateRangeLabel()),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Opening Bal.: Rs. ${_formatAmount(0)}'),
              pw.Text('Closing Bal.: Rs. ${_formatBalance(runningBalance)}'),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Date',
              'Reminder',
              'Type',
              'Invoice No',
              'Account',
              'Debit(Rs.)',
              'Credit(Rs.)',
              'Balance(Rs.)',
            ],
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerPadding: const pw.EdgeInsets.all(6),
            cellPadding: const pw.EdgeInsets.all(5),
            columnWidths: {
              0: const pw.FixedColumnWidth(62),
              1: const pw.FixedColumnWidth(70),
              2: const pw.FixedColumnWidth(44),
              3: const pw.FixedColumnWidth(70),
              4: const pw.FlexColumnWidth(2.2),
              5: const pw.FixedColumnWidth(64),
              6: const pw.FixedColumnWidth(64),
              7: const pw.FixedColumnWidth(70),
            },
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(
                'Grand Total Debit: ${_formatAmount(totalDebit)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(width: 24),
              pw.Text(
                'Grand Total Credit: ${_formatAmount(totalCredit)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(width: 24),
              pw.Text(
                'Total Balance: ${_formatBalance(runningBalance)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  void _showExportMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<File> _savePdfToFile(Uint8List bytes) async {
    // macOS app sandbox may not allow writing to the Downloads container path.
    // Save inside the app's documents directory so the file is always writable.
    final directory = await getApplicationDocumentsDirectory();
    await directory.create(recursive: true);
    final file = File(path.join(directory.path, _pdfFileName()));
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> _openPdfFile(File file) async {
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      _showExportMessage('PDF saved to: ${file.path}');
    }
  }

  Future<void> _sharePdfViaWhatsApp(File file) async {
    if (Platform.isAndroid) {
      try {
        final success = await _whatsappChannel.invokeMethod<bool>(
          'sharePdfToWhatsApp',
          {'path': file.path},
        );
        if (success == true) {
          return;
        }
      } catch (_) {
        // Continue to fallback share methods.
      }

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Ledger PDF for ${widget.company.name}',
      );
      return;
    }

    final message = 'Ledger PDF for ${widget.company.name}';

    try {
      await Share.shareXFiles(
        [XFile(file.path)],
        text: message,
      );
      return;
    } catch (_) {
      // Continue to fallback text-only WhatsApp share if file sharing fails.
    }

    final encodedMessage = Uri.encodeComponent(message);
    final whatsappUri = Uri.parse('whatsapp://send?text=$encodedMessage');

    if (await canLaunchUrl(whatsappUri)) {
      await launchUrl(whatsappUri);
      return;
    }

    final whatsappWebUri =
        Uri.parse('https://web.whatsapp.com/send?text=$encodedMessage');
    if (await canLaunchUrl(whatsappWebUri)) {
      await launchUrl(whatsappWebUri, mode: LaunchMode.externalApplication);
      return;
    }

    await Share.shareXFiles(
      [XFile(file.path)],
      text: message,
    );
  }

  Future<void> _exportLedger({required bool shareViaWhatsApp}) async {
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      final transactions = await _loadCurrentTransactions();
      if (transactions.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No transactions available to export.')),
        );
        return;
      }

      final pdfBytes = await _buildLedgerPdf(transactions);
      final file = await _savePdfToFile(pdfBytes);

      if (shareViaWhatsApp) {
        await _sharePdfViaWhatsApp(file);
      } else {
        await _openPdfFile(file);
      }
    } catch (error) {
      _showExportMessage('Could not export ledger right now: $error');
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Widget _buildStatement(List<LedgerTransaction> transactions) {
    final sortedTransactions = _sortedTransactions(transactions);

    final totalCredit = sortedTransactions
        .where(_isCredit)
        .fold<double>(0, (sum, tx) => sum + tx.amount);
    final totalDebit = sortedTransactions
        .where((tx) => !_isCredit(tx))
        .fold<double>(0, (sum, tx) => sum + tx.amount);

    double runningBalance = 0;
    final rows = <DataRow>[];

    for (final tx in sortedTransactions) {
      final credit = _isCredit(tx) ? tx.amount : 0.0;
      final debit = _isCredit(tx) ? 0.0 : tx.amount;
      if (!tx.isCleared) {
        runningBalance += credit - debit;
      }
      final rowColor =
          tx.isCleared ? Colors.red.shade700 : Colors.green.shade700;
      final rowTint = tx.isCleared ? Colors.red.shade50 : Colors.green.shade50;
      final rowTextStyle = TextStyle(
        color: rowColor,
        fontWeight: FontWeight.w600,
      );

      rows.add(
        DataRow(
          color: WidgetStatePropertyAll(rowTint),
          cells: [
            DataCell(Text(DateFormat('dd-MM-yyyy').format(tx.date),
                style: rowTextStyle)),
            DataCell(Text(_daysAgoLabel(tx.date), style: rowTextStyle)),
            DataCell(Text(_typeLabel(tx), style: rowTextStyle)),
            DataCell(Text(tx.invoiceNumber, style: rowTextStyle)),
            DataCell(
              SizedBox(
                width: 240,
                child: Text(_accountLabel(tx), style: rowTextStyle),
              ),
            ),
            DataCell(Text(debit == 0 ? '-' : _formatAmount(debit),
                style: rowTextStyle)),
            DataCell(Text(credit == 0 ? '-' : _formatAmount(credit),
                style: rowTextStyle)),
            DataCell(Text(_formatBalance(runningBalance), style: rowTextStyle)),
            DataCell(
              Text(
                tx.isCleared ? 'Cleared' : 'Pending',
                style: rowTextStyle.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tx.invoiceNumber.isNotEmpty)
                    Tooltip(
                      message: tx.isCleared
                          ? 'Mark as unpaid'
                          : 'Mark as paid',
                      child: IconButton(
                        icon: Icon(
                          tx.isCleared
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                          color: tx.isCleared ? Colors.green : Colors.grey,
                        ),
                        tooltip: tx.isCleared
                            ? 'Mark as unpaid'
                            : 'Mark as paid',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            _toggleInvoicePaymentStatus(tx.invoiceNumber, tx.isCleared),
                      ),
                    ),
                  IconButton(
                    icon: Icon(Icons.edit_outlined, color: rowColor),
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showAddTransaction(tx),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: rowColor),
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _confirmDeleteTransaction(tx.id!),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x11000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.company.name.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Account Ledger',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  _dateRangeLabel(),
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('Opening Bal.: Rs. ${_formatAmount(0)}'),
                    Text('Closing Bal.: Rs. ${_formatBalance(runningBalance)}'),
                  ],
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.black12,
                    ),
                    child: DataTable(
                      headingRowColor:
                          WidgetStatePropertyAll(Colors.grey.shade200),
                      columns: const [
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Reminder')),
                        DataColumn(label: Text('Type')),
                        DataColumn(label: Text('Invoice No')),
                        DataColumn(label: Text('Account')),
                        DataColumn(label: Text('Debit(Rs.)')),
                        DataColumn(label: Text('Credit(Rs.)')),
                        DataColumn(label: Text('Balance(Rs.)')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: rows,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      Text(
                        'Grand Total Debit: ${_formatAmount(totalDebit)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Grand Total Credit: ${_formatAmount(totalCredit)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Total Balance: ${_formatBalance(runningBalance)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyN):
            const AddTransactionIntent(),
      },
      child: Actions(
        actions: {
          AddTransactionIntent: CallbackAction<AddTransactionIntent>(
            onInvoke: (intent) => _showAddTransaction(),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.company.name),
              actions: [
                IconButton(
                  icon: _exporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: 'Save PDF',
                  onPressed: _exporting
                      ? null
                      : () => _exportLedger(shareViaWhatsApp: false),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: 'Share via WhatsApp',
                  onPressed: _exporting
                      ? null
                      : () => _exportLedger(shareViaWhatsApp: true),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_alt_off),
                  tooltip: 'Clear filters',
                  onPressed: _clearFilters,
                ),
                IconButton(
                  icon: const Icon(Icons.date_range),
                  tooltip: 'Filter by date',
                  onPressed: _pickDateRange,
                ),
              ],
            ),
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFF3F1EA), Color(0xFFE7E1D2)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: 'Search category, payment mode or note',
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.arrow_back),
                                tooltip: 'Back to full list',
                                onPressed: _clearSearch,
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.trim();
                          _refresh();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _dateRangeLabel(),
                            style: TextStyle(
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.date_range),
                          label: const Text('Date Filter'),
                          onPressed: _pickDateRange,
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _clearFilters,
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: FutureBuilder<List<LedgerTransaction>>(
                        future: _transactionsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          final transactions = snapshot.data ?? [];
                          if (transactions.isEmpty) {
                            return const Center(
                              child: Text(
                                  'No transactions yet. Add one using the button below.'),
                            );
                          }
                          return _buildStatement(transactions);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Add Transaction'),
              onPressed: () => _showAddTransaction(),
            ),
          ),
        ),
      ),
    );
  }
}
