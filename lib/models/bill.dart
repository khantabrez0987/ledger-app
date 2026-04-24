import 'ledger_mode.dart';

enum BillStatus { unpaid, partial, paid }

class Bill {
  final int? id;
  final String company;
  final String billId; // unique bill identifier (e.g., INV001)
  final DateTime date;
  final double totalAmount;
  final double paidAmount;
  final BillStatus status;
  final LedgerMode ledgerMode;
  final DateTime createdAt;
  final DateTime updatedAt;

  Bill({
    this.id,
    required this.company,
    required this.billId,
    required this.date,
    required this.totalAmount,
    this.paidAmount = 0.0,
    BillStatus? status,
    this.ledgerMode = LedgerMode.sales,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        status = status ?? _calculateStatus(totalAmount, paidAmount ?? 0.0);

  // Calculate bill status based on paid amount
  static BillStatus _calculateStatus(double total, double paid) {
    if (paid >= total) {
      return BillStatus.paid;
    } else if (paid > 0) {
      return BillStatus.partial;
    }
    return BillStatus.unpaid;
  }

  // Calculate remaining amount to be paid
  double get remainingAmount => totalAmount - paidAmount;

  // Check if bill is fully paid
  bool get isFullyPaid => remainingAmount <= 0;

  // Percentage paid
  double get percentagePaid => (paidAmount / totalAmount) * 100;

  factory Bill.fromMap(Map<String, Object?> map) {
    return Bill(
      id: map['id'] as int?,
      company: map['company'] as String,
      billId: map['bill_id'] as String,
      date: DateTime.parse(map['date'] as String),
      totalAmount: (map['total_amount'] as num).toDouble(),
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0.0,
      status: BillStatus.values.firstWhere(
        (status) => status.name == (map['status'] as String?),
        orElse: () => BillStatus.unpaid,
      ),
      ledgerMode: LedgerMode.values.firstWhere(
        (mode) => mode.name == (map['ledger_mode'] as String? ?? 'sales'),
        orElse: () => LedgerMode.sales,
      ),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String? ?? map['created_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'company': company,
      'bill_id': billId,
      'date': date.toIso8601String(),
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'status': status.name,
      'ledger_mode': ledgerMode.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Bill copyWith({
    int? id,
    String? company,
    String? billId,
    DateTime? date,
    double? totalAmount,
    double? paidAmount,
    BillStatus? status,
    LedgerMode? ledgerMode,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Bill(
      id: id ?? this.id,
      company: company ?? this.company,
      billId: billId ?? this.billId,
      date: date ?? this.date,
      totalAmount: totalAmount ?? this.totalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      status: status ?? this.status,
      ledgerMode: ledgerMode ?? this.ledgerMode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class BillPayment {
  final int? id;
  final int billId;
  final double paymentAmount;
  final DateTime paymentDate;
  final String paymentMode; // CASH, NEFT, RTGS, CHQ
  final String notes;
  final DateTime createdAt;

  BillPayment({
    this.id,
    required this.billId,
    required this.paymentAmount,
    required this.paymentDate,
    required this.paymentMode,
    this.notes = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory BillPayment.fromMap(Map<String, Object?> map) {
    return BillPayment(
      id: map['id'] as int?,
      billId: map['bill_id'] as int,
      paymentAmount: (map['payment_amount'] as num).toDouble(),
      paymentDate: DateTime.parse(map['payment_date'] as String),
      paymentMode: map['payment_mode'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'bill_id': billId,
      'payment_amount': paymentAmount,
      'payment_date': paymentDate.toIso8601String(),
      'payment_mode': paymentMode,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  BillPayment copyWith({
    int? id,
    int? billId,
    double? paymentAmount,
    DateTime? paymentDate,
    String? paymentMode,
    String? notes,
    DateTime? createdAt,
  }) {
    return BillPayment(
      id: id ?? this.id,
      billId: billId ?? this.billId,
      paymentAmount: paymentAmount ?? this.paymentAmount,
      paymentDate: paymentDate ?? this.paymentDate,
      paymentMode: paymentMode ?? this.paymentMode,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
