import 'package:flutter/material.dart';
import '../models/ledger_mode.dart';
import '../widgets/company_logo.dart';
import 'company_list_screen.dart';

class LedgerTypeSelectionScreen extends StatelessWidget {
  const LedgerTypeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Ledger Type'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CompanyLogo(height: 220),
            const SizedBox(height: 20),
            const Text(
              'Select the ledger type for Khan Yarn Traders.',
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const CompanyListScreen(mode: LedgerMode.sales),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text('Sales Ledger', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const CompanyListScreen(mode: LedgerMode.purchase),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text('Purchase Ledger', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
