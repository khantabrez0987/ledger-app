import 'ledger_mode.dart';

class LedgerTransaction {
  final int? id;
  final String company;
  final LedgerMode ledgerMode;
  final String type;
  final double amount;
  final String category;
  final String note;
  final String paymentMode;
  final String fileNumber;
  final String invoiceNumber;
  final bool isCleared;
  final DateTime date;

  LedgerTransaction({
    this.id,
    required this.company,
    this.ledgerMode = LedgerMode.sales,
    required this.type,
    required this.amount,
    required this.category,
    required this.note,
    required this.paymentMode,
    required this.fileNumber,
    required this.invoiceNumber,
    this.isCleared = false,
    required this.date,
  });

  factory LedgerTransaction.fromMap(Map<String, Object?> map) {
    return LedgerTransaction(
      id: map['id'] as int?,
      company: map['company'] as String,
      ledgerMode: LedgerMode.values.firstWhere(
        (mode) => mode.name == (map['ledger_mode'] as String? ?? 'sales'),
        orElse: () => LedgerMode.sales,
      ),
      type: map['type'] as String,
      amount: (map['amount'] as num).toDouble(),
      category: map['category'] as String? ?? '',
      note: map['note'] as String? ?? '',
      paymentMode: map['payment_mode'] as String? ?? '',
      fileNumber: map['file_number'] as String? ?? '',
      invoiceNumber: map['invoice_number'] as String? ?? '',
      isCleared: (map['is_cleared'] as int?) == 1,
      date: DateTime.parse(map['date'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'company': company,
      'ledger_mode': ledgerMode.name,
      'type': type,
      'amount': amount,
      'category': category,
      'note': note,
      'payment_mode': paymentMode,
      'file_number': fileNumber,
      'invoice_number': invoiceNumber,
      'is_cleared': isCleared ? 1 : 0,
      'date': date.toIso8601String(),
    };
  }

  LedgerTransaction copyWith({
    int? id,
    String? company,
    LedgerMode? ledgerMode,
    String? type,
    double? amount,
    String? category,
    String? note,
    String? paymentMode,
    String? fileNumber,
    String? invoiceNumber,
    bool? isCleared,
    DateTime? date,
  }) {
    return LedgerTransaction(
      id: id ?? this.id,
      company: company ?? this.company,
      ledgerMode: ledgerMode ?? this.ledgerMode,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      note: note ?? this.note,
      paymentMode: paymentMode ?? this.paymentMode,
      fileNumber: fileNumber ?? this.fileNumber,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      isCleared: isCleared ?? this.isCleared,
      date: date ?? this.date,
    );
  }
}
