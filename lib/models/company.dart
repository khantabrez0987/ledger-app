import 'ledger_mode.dart';

class Company {
  final int? id;
  final String name;
  final String address;
  final String mobileNumber;
  final LedgerMode ledgerMode;
  final DateTime createdAt;

  Company({
    this.id,
    required this.name,
    this.address = '',
    this.mobileNumber = '',
    this.ledgerMode = LedgerMode.sales,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Company.fromMap(Map<String, Object?> map) {
    return Company(
      id: map['id'] as int?,
      name: map['name'] as String,
      address: (map['address'] as String?) ?? '',
      mobileNumber: (map['mobile_number'] as String?) ?? '',
      ledgerMode: LedgerMode.values.firstWhere(
        (mode) => mode.name == (map['ledger_mode'] as String? ?? 'sales'),
        orElse: () => LedgerMode.sales,
      ),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'mobile_number': mobileNumber,
      'ledger_mode': ledgerMode.name,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
