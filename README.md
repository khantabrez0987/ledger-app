# Ledger Desktop App for macOS

A simple offline Flutter ledger application for macOS using SQLite.

## Features

- Add and manage multiple companies
- Add income and expense transactions
- Edit and delete transactions
- Company-specific ledger view
- Total income, total expense, and balance summary
- Search by category or note
- Filter transactions by date range
- Simple income vs expense chart
- Works offline with local SQLite database

## Project Files

- `lib/main.dart` - app entry point
- `lib/db_helper.dart` - SQLite helper and CRUD operations
- `lib/models/company.dart` - company data model
- `lib/models/ledger_transaction.dart` - transaction data model
- `lib/screens/company_list_screen.dart` - company list and selection screen
- `lib/screens/add_company_screen.dart` - add company form
- `lib/screens/ledger_screen.dart` - ledger view for selected company
- `lib/screens/add_edit_transaction_screen.dart` - add/edit transaction form
- `lib/widgets/transaction_tile.dart` - transaction list item widget
- `lib/widgets/stat_card.dart` - summary cards for income/expense/balance
- `lib/widgets/income_expense_chart.dart` - simple chart widget

## Setup Instructions for macOS

1. Install Flutter and enable macOS desktop support:

```bash
flutter channel stable
flutter upgrade
flutter config --enable-macos-desktop
```

2. Create a new Flutter project or open this folder in VS Code.

If you are starting from scratch, run:

```bash
flutter create ledger_app
cd ledger_app
```

3. Replace the generated `pubspec.yaml` and `lib/` folder with the files in this repository.

4. Get dependencies:

```bash
flutter pub get
```

5. If macOS support is not initialized yet, run:

```bash
flutter create .
```

6. Run the app on macOS:

```bash
flutter run -d macos
```

## Notes

- The app uses `sqflite_common_ffi` for desktop SQLite access.
- Transaction dates are stored in ISO 8601 format.
- Data is saved into a local database file in the application documents folder.

## Troubleshooting

- If macOS desktop build is unavailable, verify your Flutter installation with:

```bash
flutter doctor
```

- If you encounter package issues, run:

```bash
flutter pub get
```

## Optional improvements

- Add company deletion and transaction export
- Add recurring transactions
- Add categories management
- Add support for multiple currencies
