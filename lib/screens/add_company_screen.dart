import 'package:flutter/material.dart';
import '../db_helper.dart';
import '../models/company.dart';
import '../models/ledger_mode.dart';

class AddCompanyScreen extends StatefulWidget {
  final Company? company;
  final LedgerMode mode;

  const AddCompanyScreen({super.key, this.company, required this.mode});

  @override
  State<AddCompanyScreen> createState() => _AddCompanyScreenState();
}

class _AddCompanyScreenState extends State<AddCompanyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _mobileNumberController = TextEditingController();
  final db = DbHelper.instance;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final company = widget.company;
    if (company != null) {
      _nameController.text = company.name;
      _addressController.text = company.address;
      _mobileNumberController.text = company.mobileNumber;
    }
  }

  Future<void> _saveCompany() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final companyName = _nameController.text.trim();
    final address = _addressController.text.trim();
    final mobileNumber = _mobileNumberController.text.trim();
    final currentCompany = widget.company;

    try {
      if (currentCompany == null) {
        final company = Company(
          name: companyName,
          address: address,
          mobileNumber: mobileNumber,
          ledgerMode: widget.mode,
        );
        await db.addCompany(company);
      } else {
        final company = Company(
          id: currentCompany.id,
          name: companyName,
          address: address,
          mobileNumber: mobileNumber,
          ledgerMode: currentCompany.ledgerMode,
          createdAt: currentCompany.createdAt,
        );
        await db.updateCompany(
          company: company,
          previousName: currentCompany.name,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save company. The name may already exist.'),
        ),
      );
      return;
    }

    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _mobileNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.company != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Company' : 'Add Company')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Company Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a company name.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
                minLines: 2,
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an address.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mobileNumberController,
                decoration: const InputDecoration(
                  labelText: 'Mobile Number',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a mobile number.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _saveCompany,
                child: _saving
                    ? const CircularProgressIndicator()
                    : Text(isEditing ? 'Update Company' : 'Save Company'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
