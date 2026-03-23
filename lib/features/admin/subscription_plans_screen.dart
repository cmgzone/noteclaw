import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/billing_catalog_service.dart';

class SubscriptionPlansScreen extends ConsumerStatefulWidget {
  const SubscriptionPlansScreen({super.key});

  @override
  ConsumerState<SubscriptionPlansScreen> createState() =>
      _SubscriptionPlansScreenState();
}

class _SubscriptionPlansScreenState
    extends ConsumerState<SubscriptionPlansScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isLoading = false;
  List<AdminSubscriptionPlan> _plans = const [];
  List<AdminCreditPackage> _packages = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(billingCatalogServiceProvider);
      final plans = await service.listPlans();
      final packages = await service.listPackages();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _packages = packages;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load billing catalog: $error')),
      );
    }
  }

  Future<void> _deletePlan(AdminSubscriptionPlan plan) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete plan?'),
            content: Text('Delete "${plan.name}" from the billing catalog?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      await ref.read(billingCatalogServiceProvider).deletePlan(plan.id);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete plan: $error')),
      );
    }
  }

  Future<void> _deletePackage(AdminCreditPackage package) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete package?'),
            content:
                Text('Delete "${package.name}" from the credit packages list?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      await ref.read(billingCatalogServiceProvider).deletePackage(package.id);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete package: $error')),
      );
    }
  }

  Future<void> _showPlanDialog([AdminSubscriptionPlan? plan]) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _PlanDialog(
        plan: plan,
        onSaved: _loadData,
      ),
    );
  }

  Future<void> _showPackageDialog([AdminCreditPackage? package]) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _PackageDialog(
        package: package,
        onSaved: _loadData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing Catalog'),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Plans'),
            Tab(text: 'Credit Packs'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _showPlanDialog();
          } else {
            _showPackageDialog();
          }
        },
        icon: const Icon(Icons.add),
        label: Text(_tabController.index == 0 ? 'Add Plan' : 'Add Package'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _plans.isEmpty
                    ? const _EmptyState(
                        icon: Icons.credit_card,
                        title: 'No plans yet',
                        subtitle:
                            'Create paid or free plans and optionally map them to Google Play subscription product IDs.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _plans.length,
                        itemBuilder: (context, index) {
                          final plan = _plans[index];
                          final chipColor = plan.isFreePlan
                              ? Colors.green
                              : plan.googlePlayProductId?.isNotEmpty == true
                                  ? Colors.blue
                                  : Colors.orange;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          plan.name,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      _StatusChip(
                                        label: plan.isFreePlan
                                            ? 'FREE'
                                            : plan.googlePlayProductId?.isNotEmpty ==
                                                    true
                                                ? 'PLAY READY'
                                                : 'NEEDS PLAY ID',
                                        color: chipColor,
                                      ),
                                    ],
                                  ),
                                  if ((plan.description ?? '').trim().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(plan.description!.trim()),
                                    ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      _MetaText(
                                        label: 'Credits/mo',
                                        value: '${plan.creditsPerMonth}',
                                      ),
                                      _MetaText(
                                        label: 'Price',
                                        value: '\$${plan.price.toStringAsFixed(2)}',
                                      ),
                                      _MetaText(
                                        label: 'Subscribers',
                                        value: '${plan.subscriberCount}',
                                      ),
                                      _MetaText(
                                        label: 'Status',
                                        value:
                                            plan.isActive ? 'Active' : 'Inactive',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    plan.googlePlayProductId?.isNotEmpty == true
                                        ? 'Google Play ID: ${plan.googlePlayProductId}'
                                        : 'Google Play ID: not set',
                                    style: TextStyle(
                                      color:
                                          scheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () => _showPlanDialog(plan),
                                        icon: const Icon(Icons.edit_outlined),
                                        label: const Text('Edit'),
                                      ),
                                      const SizedBox(width: 12),
                                      OutlinedButton.icon(
                                        onPressed: () => _deletePlan(plan),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                        ),
                                        label: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                _packages.isEmpty
                    ? const _EmptyState(
                        icon: Icons.payments_outlined,
                        title: 'No credit packs yet',
                        subtitle:
                            'Create consumable credit packs and map them to Google Play in-app product IDs.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _packages.length,
                        itemBuilder: (context, index) {
                          final package = _packages[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          package.name,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      _StatusChip(
                                        label: package.googlePlayProductId
                                                    ?.isNotEmpty ==
                                                true
                                            ? 'PLAY READY'
                                            : 'NEEDS PLAY ID',
                                        color: package.googlePlayProductId
                                                    ?.isNotEmpty ==
                                                true
                                            ? Colors.blue
                                            : Colors.orange,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      _MetaText(
                                        label: 'Credits',
                                        value: '${package.credits}',
                                      ),
                                      _MetaText(
                                        label: 'Price',
                                        value:
                                            '\$${package.price.toStringAsFixed(2)}',
                                      ),
                                      _MetaText(
                                        label: 'Status',
                                        value: package.isActive
                                            ? 'Active'
                                            : 'Inactive',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    package.googlePlayProductId?.isNotEmpty ==
                                            true
                                        ? 'Google Play ID: ${package.googlePlayProductId}'
                                        : 'Google Play ID: not set',
                                    style: TextStyle(
                                      color:
                                          scheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            _showPackageDialog(package),
                                        icon: const Icon(Icons.edit_outlined),
                                        label: const Text('Edit'),
                                      ),
                                      const SizedBox(width: 12),
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            _deletePackage(package),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                        ),
                                        label: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
    );
  }
}

class _PlanDialog extends ConsumerStatefulWidget {
  final AdminSubscriptionPlan? plan;
  final Future<void> Function() onSaved;

  const _PlanDialog({
    this.plan,
    required this.onSaved,
  });

  @override
  ConsumerState<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends ConsumerState<_PlanDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _creditsController;
  late final TextEditingController _priceController;
  late final TextEditingController _googlePlayProductIdController;
  late bool _isActive;
  late bool _isFreePlan;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.plan?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.plan?.description ?? '');
    _creditsController = TextEditingController(
      text: '${widget.plan?.creditsPerMonth ?? 30}',
    );
    _priceController = TextEditingController(
      text: widget.plan == null ? '0.00' : widget.plan!.price.toStringAsFixed(2),
    );
    _googlePlayProductIdController = TextEditingController(
      text: widget.plan?.googlePlayProductId ?? '',
    );
    _isActive = widget.plan?.isActive ?? true;
    _isFreePlan = widget.plan?.isFreePlan ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _creditsController.dispose();
    _priceController.dispose();
    _googlePlayProductIdController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final service = ref.read(billingCatalogServiceProvider);
      final googlePlayId = _googlePlayProductIdController.text.trim();

      if (widget.plan == null) {
        await service.createPlan(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          creditsPerMonth: int.parse(_creditsController.text.trim()),
          price: double.parse(_priceController.text.trim()),
          isActive: _isActive,
          isFreePlan: _isFreePlan,
          googlePlayProductId: googlePlayId.isEmpty ? null : googlePlayId,
        );
      } else {
        await service.updatePlan(
          id: widget.plan!.id,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          creditsPerMonth: int.parse(_creditsController.text.trim()),
          price: double.parse(_priceController.text.trim()),
          isActive: _isActive,
          isFreePlan: _isFreePlan,
          googlePlayProductId: googlePlayId.isEmpty ? null : googlePlayId,
        );
      }

      if (!mounted) return;
      await widget.onSaved();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save plan: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.plan == null ? 'Add Plan' : 'Edit Plan'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? 'Name is required'
                          : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _creditsController,
                  decoration:
                      const InputDecoration(labelText: 'Credits per month'),
                  keyboardType: TextInputType.number,
                  validator: _validateInt,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(labelText: 'Price (USD)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _validateDouble,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _googlePlayProductIdController,
                  decoration: const InputDecoration(
                    labelText: 'Google Play product ID',
                    hintText: 'noteclaw_pro_monthly',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _isFreePlan,
                  onChanged: (value) => setState(() => _isFreePlan = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Free plan'),
                  subtitle: const Text(
                    'Free plans do not need a Google Play product ID.',
                  ),
                ),
                SwitchListTile(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _PackageDialog extends ConsumerStatefulWidget {
  final AdminCreditPackage? package;
  final Future<void> Function() onSaved;

  const _PackageDialog({
    this.package,
    required this.onSaved,
  });

  @override
  ConsumerState<_PackageDialog> createState() => _PackageDialogState();
}

class _PackageDialogState extends ConsumerState<_PackageDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _creditsController;
  late final TextEditingController _priceController;
  late final TextEditingController _googlePlayProductIdController;
  late bool _isActive;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.package?.name ?? '');
    _creditsController = TextEditingController(
      text: '${widget.package?.credits ?? 100}',
    );
    _priceController = TextEditingController(
      text:
          widget.package == null ? '0.00' : widget.package!.price.toStringAsFixed(2),
    );
    _googlePlayProductIdController = TextEditingController(
      text: widget.package?.googlePlayProductId ?? '',
    );
    _isActive = widget.package?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _creditsController.dispose();
    _priceController.dispose();
    _googlePlayProductIdController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final service = ref.read(billingCatalogServiceProvider);
      final googlePlayId = _googlePlayProductIdController.text.trim();

      if (widget.package == null) {
        await service.createPackage(
          name: _nameController.text.trim(),
          credits: int.parse(_creditsController.text.trim()),
          price: double.parse(_priceController.text.trim()),
          isActive: _isActive,
          googlePlayProductId: googlePlayId.isEmpty ? null : googlePlayId,
        );
      } else {
        await service.updatePackage(
          id: widget.package!.id,
          name: _nameController.text.trim(),
          credits: int.parse(_creditsController.text.trim()),
          price: double.parse(_priceController.text.trim()),
          isActive: _isActive,
          googlePlayProductId: googlePlayId.isEmpty ? null : googlePlayId,
        );
      }

      if (!mounted) return;
      await widget.onSaved();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save package: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.package == null ? 'Add Package' : 'Edit Package'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? 'Name is required'
                          : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _creditsController,
                  decoration: const InputDecoration(labelText: 'Credits'),
                  keyboardType: TextInputType.number,
                  validator: _validateInt,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(labelText: 'Price (USD)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _validateDouble,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _googlePlayProductIdController,
                  decoration: const InputDecoration(
                    labelText: 'Google Play product ID',
                    hintText: 'noteclaw_credits_starter',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  final String label;
  final String value;

  const _MetaText({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

String? _validateInt(String? value) {
  final parsed = int.tryParse(value?.trim() ?? '');
  if (parsed == null || parsed < 0) {
    return 'Enter a valid whole number';
  }
  return null;
}

String? _validateDouble(String? value) {
  final parsed = double.tryParse(value?.trim() ?? '');
  if (parsed == null || parsed < 0) {
    return 'Enter a valid number';
  }
  return null;
}
