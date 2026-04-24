# Payment Against Bill Feature - Implementation Guide

## Overview
This document describes the new "Payment Against Bill" feature added to the Ledger App. The feature allows users to apply payments against specific bills or have payments auto-adjust to the oldest unpaid bills using FIFO logic.

---

## 1. NEW DATA MODELS

### Bill Model (`lib/models/bill.dart`)
Represents an invoice/bill with partial payment tracking:

```dart
class Bill {
  final int? id;
  final String company;
  final String billId;           // Unique invoice ID (e.g., INV001)
  final DateTime date;
  final double totalAmount;      // Total bill amount
  final double paidAmount;       // Amount paid so far (default: 0)
  final BillStatus status;       // unpaid / partial / paid
  final LedgerMode ledgerMode;   // sales / purchase
  final DateTime createdAt;
  final DateTime updatedAt;

  double get remainingAmount => totalAmount - paidAmount;
  bool get isFullyPaid => remainingAmount <= 0;
  double get percentagePaid => (paidAmount / totalAmount) * 100;
}

enum BillStatus { unpaid, partial, paid }
```

### BillPayment Model
Tracks individual payments applied to a bill:

```dart
class BillPayment {
  final int? id;
  final int billId;              // Foreign key to bills table
  final double paymentAmount;
  final DateTime paymentDate;
  final String paymentMode;      // CASH, NEFT, RTGS, CHQ
  final String notes;
  final DateTime createdAt;
}
```

---

## 2. DATABASE CHANGES

### New Tables Created

#### `bills` table
```sql
CREATE TABLE bills(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  company TEXT NOT NULL,
  bill_id TEXT NOT NULL,
  date TEXT NOT NULL,
  total_amount REAL NOT NULL,
  paid_amount REAL NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'unpaid',
  ledger_mode TEXT NOT NULL DEFAULT 'sales',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(company, bill_id, ledger_mode)
)
```

#### `bill_payments` table
```sql
CREATE TABLE bill_payments(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  bill_id INTEGER NOT NULL,
  payment_amount REAL NOT NULL,
  payment_date TEXT NOT NULL,
  payment_mode TEXT NOT NULL DEFAULT 'CASH',
  notes TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  FOREIGN KEY(bill_id) REFERENCES bills(id) ON DELETE CASCADE
)
```

**Backward Compatibility:** Existing data is NOT affected. New tables are created during first run or migration.

---

## 3. NEW DATABASE FUNCTIONS (`db_helper.dart`)

### Bill Creation & Retrieval

#### `createBill(Bill bill)`
Creates a new bill in the database.

```dart
await db.createBill(Bill(
  company: 'Customer A',
  billId: 'INV-001',
  date: DateTime.now(),
  totalAmount: 5000.0,
  ledgerMode: LedgerMode.sales,
));
```

#### `getBillsByCompany(String companyName, {LedgerMode? mode})`
Retrieves all bills for a company (sorted by date, newest first).

#### `getBillByBillId(String companyName, String billId, {LedgerMode? mode})`
Gets a specific bill by its ID.

#### `getBillsByStatus(String companyName, BillStatus status, {LedgerMode? mode})`
Gets bills filtered by status (unpaid/partial/paid).

### Payment Logic

#### `applyPaymentToBill({required int billId, required double paymentAmount, required String paymentMode, String notes})`
Applies a payment to a specific bill:
- Creates a BillPayment record
- Updates bill's `paid_amount` and `status` automatically
- **Prevents overpayment** (throws exception if payment exceeds remaining amount)
- Runs in a database transaction

**Example:**
```dart
await db.applyPaymentToBill(
  billId: 1,
  paymentAmount: 1000.0,
  paymentMode: 'CASH',
  notes: 'Partial payment',
);
```

#### `autoAdjustPayment({required String companyName, required double paymentAmount, required String paymentMode, String notes, LedgerMode? mode})`
**FIFO Logic:** Applies payment to oldest unpaid/partial bills in sequence:
1. Fetches unpaid and partial bills sorted by date (oldest first)
2. Loops through bills, deducting payment amount from remaining balance
3. Updates each bill's `paid_amount` and `status` automatically
4. Returns list of bill IDs that received payment
5. Continues until payment is exhausted or all bills are paid

**Example:**
```dart
final billsReceivingPayment = await db.autoAdjustPayment(
  companyName: 'Customer A',
  paymentAmount: 2500.0,
  paymentMode: 'NEFT',
  mode: LedgerMode.sales,
);
print('Payment applied to ${billsReceivingPayment.length} bill(s)');
```

### Balance Calculation

#### `calculateTotalDueByBills(String companyName, {LedgerMode? mode})`
Calculates total outstanding amount from all unpaid/partial bills:
```
total_due = SUM(bill.total_amount - bill.paid_amount) 
           WHERE status IN ('unpaid', 'partial')
```

**Replaces old balance logic for bill-specific calculations.**

### Additional Utilities

- `getPaymentsByBill(int billId)` - Get all payments made against a bill
- `updateBillStatus(int billId, BillStatus status)` - Manual status update
- `deleteBill(int billId)` - Delete bill and associated payments
- `getUnpaidBills(String companyName, {LedgerMode? mode})` - Get only unpaid bills
- `getPartiallyPaidBills(String companyName, {LedgerMode? mode})` - Get partially paid bills

---

## 4. UI CHANGES

### Modified: Add Transaction Screen (`add_edit_transaction_screen.dart`)

#### New Features (for Credit/Payment Transactions Only):
1. **Bill Payment Toggle:** "Apply to specific bill" checkbox
2. **Bill Selection Dropdown:** Shows available unpaid/partial bills with remaining amount
3. **Auto-Adjust Option:** If toggle is off, payment auto-adjusts to oldest bills

#### New State Variables:
```dart
bool _applyToBill = false;         // Toggle for bill application
int? _selectedBillId;              // Selected bill ID
List<Bill> _availableBills = [];  // Bills available for payment
late Future<void> _loadBillsFuture; // Async bills loading
```

#### UI Section Added:
When transaction type is "credit" (payment/receipt) and bills exist:
```
┌─────────────────────────────────────┐
│ Bill Payment Options                │
├─────────────────────────────────────┤
│ ☐ Apply to specific bill            │
│   Uncheck to auto-adjust to oldest  │
│   unpaid bills                      │
│                                      │
│ [Dropdown: Select Bill]  ← optional │
└─────────────────────────────────────┘
```

#### Save Logic:
When saving a payment (credit/income type):
- **If `_applyToBill` = true & bill selected:** Call `applyPaymentToBill()`
- **If `_applyToBill` = false & bills exist:** Call `autoAdjustPayment()`
- Shows success/error messages to user
- Transaction record is still saved normally

### Updated: Unpaid Bills Screen (`unpaid_bills_screen.dart`)

#### Enhancements:
1. **Shows Both Sources:**
   - Existing transaction-based unpaid invoices
   - New Bill records with partial payment status

2. **Bill Details Card for New Bills:**
   - Bill ID, date, due amount
   - **Payment progress bar** showing paid percentage
   - Status color-coded: Green (paid), Orange (partial), Red (unpaid)
   - Total amount vs paid amount breakdown

3. **Consolidated Total Outstanding:**
   - Combines both transaction-based and bill-based outstanding amounts

4. **Visual Distinction:**
   - Transaction invoices: Orange receipt icon
   - Bill records: Teal inventory icon with status color

---

## 5. INTEGRATION WITH EXISTING SYSTEM

### NO Breaking Changes ✓
- Existing transaction data remains unchanged
- Old invoice tracking via `invoice_number` and `is_cleared` still works
- Can migrate gradually from old to new system

### How They Coexist:
1. **Old System** (still works):
   - Transactions with `invoice_number` tracked as cleared/unpaid
   - Used in UnpaidBillsScreen and LedgerScreen

2. **New System** (added):
   - Bills with partial payment tracking
   - Separate payment history per bill
   - Better for detailed payment reconciliation

3. **Both Shown Together:**
   - UnpaidBillsScreen displays both types
   - Users can gradually migrate to new bill system

### Balance Calculation:
Old function `getCompanyBalance()` still calculates transaction-based balance.
New function `calculateTotalDueByBills()` calculates bill-based balance.

---

## 6. FUNCTIONS IMPLEMENTED

### Core Functions (Required by Spec)

✓ **`createBill()`** - Create a new bill  
✓ **`addPayment()`** - Payment saving (existing, extended)  
✓ **`applyPaymentToBill()`** - Apply payment to specific bill  
✓ **`autoAdjustPayment()`** - FIFO-based auto-adjustment  
✓ **`calculateBalance()`** - Bill-based total due calculation  

### Additional Utilities (Quality-of-Life)

✓ `getBillsByCompany()` - Fetch all bills for a company  
✓ `getBillsByStatus()` - Filter by payment status  
✓ `getBillByBillId()` - Get specific bill  
✓ `getPaymentsByBill()` - Get payment history  
✓ `updateBillStatus()` - Manual status update  
✓ `deleteBill()` - Delete bill and payments  
✓ `getUnpaidBills()` - Quick unpaid bills query  
✓ `getPartiallyPaidBills()` - Quick partial bills query  

---

## 7. EDGE CASES HANDLED

### ✓ Overpayment Prevention
```dart
if (newPaidAmount > bill.totalAmount) {
  throw Exception('Payment exceeds bill amount...');
}
```

### ✓ Partial Payments
- Bills automatically marked as "partial" when `0 < paid_amount < total_amount`
- Payment history preserved for audit trail

### ✓ Missing Data
- All functions check for NULL before processing
- Safe fallbacks for optional parameters
- Graceful error messages to user

### ✓ Database Consistency
- All bill payment operations run in transactions
- Foreign key constraints prevent orphaned payments
- CASCADE delete removes payments with bill

### ✓ Status Auto-Calculation
```dart
if (paid_amount >= total_amount) status = paid;
else if (paid_amount > 0) status = partial;
else status = unpaid;
```

---

## 8. USAGE EXAMPLES

### Example 1: Create a Bill
```dart
final bill = Bill(
  company: 'Khan Yarn Traders',
  billId: 'INV-2026-001',
  date: DateTime(2026, 4, 24),
  totalAmount: 50000.0,
  ledgerMode: LedgerMode.sales,
);
await db.createBill(bill);
```

### Example 2: Apply Full Payment to Specific Bill
```dart
await db.applyPaymentToBill(
  billId: 1,
  paymentAmount: 50000.0,
  paymentMode: 'NEFT',
  notes: 'Full payment received',
);
// Bill status automatically updates to 'paid'
```

### Example 3: Apply Partial Payment with Auto-Adjust
```dart
// User receives ₹35,000 - system auto-distributes to oldest unpaid bills
final appliedTo = await db.autoAdjustPayment(
  companyName: 'Khan Yarn Traders',
  paymentAmount: 35000.0,
  paymentMode: 'CASH',
  notes: 'Partial payment',
  mode: LedgerMode.sales,
);
// appliedTo = [1, 2] means payment split between bills 1 and 2
```

### Example 4: Get Outstanding Amount
```dart
final due = await db.calculateTotalDueByBills(
  'Khan Yarn Traders',
  mode: LedgerMode.sales,
);
print('Total Due: ₹$due');
```

---

## 9. CODE STYLE CONSISTENCY

✓ Follows existing naming conventions (snake_case for DB columns, camelCase for Dart)  
✓ Uses same error handling patterns  
✓ Consistent with existing model structure (fromMap/toMap pattern)  
✓ Comments added to all new functions  
✓ Matches UI design language (colors, spacing, typography)  

---

## 10. FILES MODIFIED/CREATED

### Created:
- `lib/models/bill.dart` - Bill and BillPayment models

### Modified:
- `lib/db_helper.dart` - Added bills management (900+ lines added)
- `lib/screens/add_edit_transaction_screen.dart` - Added bill selection UI
- `lib/screens/unpaid_bills_screen.dart` - Extended to show bills

### Not Modified (Backward Compatible):
- `lib/models/company.dart` ✓
- `lib/models/ledger_transaction.dart` ✓
- `lib/models/ledger_mode.dart` ✓
- All other screens remain unchanged ✓

---

## 11. TESTING CHECKLIST

- [x] Create bill and verify in database
- [x] Apply full payment to bill (status → paid)
- [x] Apply partial payment (status → partial)
- [x] Auto-adjust payment to multiple bills (FIFO order)
- [x] Prevent overpayment
- [x] Fetch payment history for bill
- [x] Calculate total due from bills
- [x] Verify UI shows bills in UnpaidBillsScreen
- [x] Verify bill selection dropdown in transaction screen
- [x] Test error handling for invalid inputs

---

## 12. FUTURE ENHANCEMENTS

Potential features not in current scope:
- Bill creation from transaction UI (currently manual)
- Payment reversal/adjustment
- Bill export to PDF
- Recurring bills
- Bill templates
- Payment reminders/notifications
- Advanced filtering/search in bills screen

---

## Summary

The "Payment Against Bill" feature successfully extends the ledger app with:
- ✓ Partial payment tracking
- ✓ FIFO auto-adjustment logic
- ✓ Overpayment prevention
- ✓ Backward-compatible data storage
- ✓ Intuitive user interface
- ✓ Full audit trail

The implementation maintains code consistency, doesn't break existing functionality, and provides clear integration points for future enhancements.
