import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../db_helper.dart';
import '../models/company.dart';
import '../models/ledger_mode.dart';
import 'add_company_screen.dart';
import 'ledger_screen.dart';
import 'unpaid_bills_screen.dart';

class CompanyListScreen extends StatefulWidget {
  const CompanyListScreen({super.key, required this.mode});

  final LedgerMode mode;

  @override
  State<CompanyListScreen> createState() => _CompanyListScreenState();
}

class CompanyWithBalance {
  final Company company;
  final double balance;

  CompanyWithBalance({required this.company, required this.balance});
}

class AddCompanyIntent extends Intent {
  const AddCompanyIntent();
}

class _CompanyListScreenState extends State<CompanyListScreen> {
  final db = DbHelper.instance;
  final _searchController = TextEditingController();
  late Future<List<CompanyWithBalance>> _companiesFuture;
  String _searchQuery = '';

  String _companySubtitle(Company company) {
    final details = <String>[
      if (company.mobileNumber.isNotEmpty) company.mobileNumber,
      if (company.address.isNotEmpty) company.address,
    ];
    if (details.isEmpty) {
      return 'Created ${company.createdAt.toLocal().toString().split(' ').first}';
    }
    return details.join(' • ');
  }

  String _formatAmount(double value) {
    return NumberFormat.currency(symbol: '', decimalDigits: 2)
        .format(value)
        .trim();
  }

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  void _loadCompanies() {
    _companiesFuture = _getCompaniesWithBalance();
  }

  Future<List<CompanyWithBalance>> _getCompaniesWithBalance() async {
    final companies = await db.getCompanies(mode: widget.mode);
    final balances = await Future.wait(
      companies.map(
          (company) => db.getCompanyBalance(company.name, mode: widget.mode)),
    );
    return List<CompanyWithBalance>.generate(
      companies.length,
      (index) => CompanyWithBalance(
        company: companies[index],
        balance: balances[index],
      ),
    );
  }

  void _refresh() {
    setState(_loadCompanies);
  }

  void _clearSearch() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openLedger(Company company) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LedgerScreen(company: company, mode: widget.mode),
      ),
    );
    _refresh();
  }

  Future<void> _showAddCompany() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddCompanyScreen(mode: widget.mode),
      ),
    );
    if (created == true) {
      _refresh();
    }
  }

  Future<void> _showEditCompany(Company company) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddCompanyScreen(company: company, mode: widget.mode),
      ),
    );
    if (updated == true) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyN):
            const AddCompanyIntent(),
      },
      child: Actions(
        actions: {
          AddCompanyIntent: CallbackAction<AddCompanyIntent>(
            onInvoke: (intent) => _showAddCompany(),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.mode == LedgerMode.sales
                  ? 'Sales Companies'
                  : 'Purchase Companies'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.receipt_long),
                  tooltip: 'Unpaid Bills',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UnpaidBillsScreen(mode: widget.mode),
                    ),
                  ),
                ),
              ],
            ),
            body: FutureBuilder<List<CompanyWithBalance>>(
              future: _companiesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final companies = snapshot.data ?? <CompanyWithBalance>[];
                if (companies.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'No companies yet. Add one to start tracking ledger entries.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            icon: const Icon(Icons.add_business),
                            label: const Text('Add Company'),
                            onPressed: _showAddCompany,
                          )
                        ],
                      ),
                    ),
                  );
                }
                final filteredCompanies = companies.where((companyWithBalance) {
                  final company = companyWithBalance.company;
                  final query = _searchQuery.toLowerCase();
                  return company.name.toLowerCase().contains(query) ||
                      company.address.toLowerCase().contains(query) ||
                      company.mobileNumber.toLowerCase().contains(query);
                }).toList();
                final totalBalance =
                    (_searchQuery.isEmpty ? companies : filteredCompanies)
                        .fold<double>(0, (sum, item) => sum + item.balance);

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          labelText: 'Search companies',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.arrow_back),
                                  tooltip: 'Back to full list',
                                  onPressed: _clearSearch,
                                )
                              : null,
                        ),
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (filteredCompanies.isEmpty)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Center(
                              child: Text(
                                _searchQuery.isEmpty
                                    ? 'No companies found.'
                                    : 'No companies match "$_searchQuery".',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Total Closing Balance',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Rs ${_formatAmount(totalBalance)}',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: totalBalance < 0
                                          ? Colors.red
                                          : Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredCompanies.length + 1,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            if (index == filteredCompanies.length) {
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Total Closing Balance',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Rs ${_formatAmount(totalBalance)}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: totalBalance < 0
                                            ? Colors.red
                                            : Colors.green[700],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            final companyWithBalance = filteredCompanies[index];
                            final company = companyWithBalance.company;
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              tileColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              title: Text(company.name,
                                  style: const TextStyle(fontSize: 18)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_companySubtitle(company)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Closing Balance: Rs ${_formatAmount(companyWithBalance.balance)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: companyWithBalance.balance < 0
                                          ? Colors.red
                                          : Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit company',
                                onPressed: () => _showEditCompany(company),
                              ),
                              onTap: () => _openLedger(company),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
            floatingActionButton: FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New Company'),
              onPressed: _showAddCompany,
            ),
          ),
        ),
      ),
    );
  }
}
