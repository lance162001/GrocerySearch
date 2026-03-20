import 'package:flutter/material.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:flutter_front_end/widgets/top_level_navigation.dart';
import 'package:provider/provider.dart';

class SuggestStorePage extends StatefulWidget {
  const SuggestStorePage({super.key});

  @override
  State<SuggestStorePage> createState() => _SuggestStorePageState();
}

class _SuggestStorePageState extends State<SuggestStorePage> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _townController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipcodeController = TextEditingController();
  int? _selectedCompanyId;
  bool _submitting = false;

  @override
  void dispose() {
    _addressController.dispose();
    _townController.dispose();
    _stateController.dispose();
    _zipcodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCompanyId == null) return;

    setState(() => _submitting = true);

    try {
      await context.read<GroceryApi>().suggestStore(
            companyId: _selectedCompanyId!,
            address: _addressController.text.trim(),
            town: _townController.text.trim(),
            state: _stateController.text.trim(),
            zipcode: _zipcodeController.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Store suggestion submitted!')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<AppState>().companies;
    final compact = MediaQuery.of(context).size.width < 420;

    return Scaffold(
      appBar: AppBar(title: const Text('Suggest Store')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(compact ? 16 : 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Know a store we should add?',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Fill in the store details below and we\'ll look into adding it.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedCompanyId,
                    decoration: const InputDecoration(
                      labelText: 'Company',
                      border: OutlineInputBorder(),
                    ),
                    items: companies
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _selectedCompanyId = value),
                    validator: (value) =>
                        value == null ? 'Please select a company' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _townController,
                    decoration: const InputDecoration(
                      labelText: 'Town / City',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _stateController,
                    decoration: const InputDecoration(
                      labelText: 'State',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _zipcodeController,
                    decoration: const InputDecoration(
                      labelText: 'Zipcode',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 5,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Required';
                      }
                      if (!RegExp(r'^\d{5}$').hasMatch(value.trim())) {
                        return 'Enter a 5-digit zipcode';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Submit Suggestion'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: TopLevelNavigationBar(
          currentDestination: AppTopLevelDestination.stores,
        ),
      ),
    );
  }
}
