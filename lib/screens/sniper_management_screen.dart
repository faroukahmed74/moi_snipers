import 'package:flutter/material.dart';
import '../models.dart';
import '../main.dart';
import '../l10n/app_localizations.dart';
import '../storage.dart';

class SniperManagementScreen extends StatefulWidget {
  const SniperManagementScreen({super.key});
  @override
  State<SniperManagementScreen> createState() => _SniperManagementScreenState();
}

class _SniperManagementScreenState extends State<SniperManagementScreen> {
  List<SniperType> snipers = [];

  @override
  void initState() {
    super.initState();
    _loadSnipers();
  }

  Future<void> _loadSnipers() async {
    final loadedSnipers = await Storage.loadSniperTypes();
    setState(() {
      snipers = loadedSnipers;
    });
  }

  Future<void> _saveSnipers() async {
    await Storage.saveSniperTypes(snipers);
  }

  void _addSniper() async {
    final newSniper = await showDialog<SniperType>(
      context: context,
      builder: (context) => const SniperDialog(),
    );
    if (newSniper != null) {
      setState(() { snipers.add(newSniper); });
      _saveSnipers();
    }
  }

  void _editSniper(int index) async {
    final updated = await showDialog<SniperType>(
      context: context,
      builder: (context) => SniperDialog(sniper: snipers[index]),
    );
    if (updated != null) {
      setState(() { snipers[index] = updated; });
      _saveSnipers();
    }
  }

  void _deleteSniper(int index) async {
    setState(() { snipers.removeAt(index); });
    await _saveSnipers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.sniperManagement)),
      body: ListView.builder(
        itemCount: snipers.length,
        itemBuilder: (context, index) {
          final sniper = snipers[index];
          return ListTile(
            title: Text(sniper.name),
            subtitle: Text('${AppLocalizations.of(context)!.bulletWeight}: ${sniper.bulletWeight}g, ${AppLocalizations.of(context)!.muzzleVelocity}: ${sniper.muzzleVelocity}m/s'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editSniper(index),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _deleteSniper(index),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSniper,
        child: const Icon(Icons.add),
        tooltip: AppLocalizations.of(context)!.addSniper,
      ),
    );
  }
}

class SniperDialog extends StatefulWidget {
  final SniperType? sniper;
  const SniperDialog({this.sniper, super.key});

  @override
  State<SniperDialog> createState() => _SniperDialogState();
}

class _SniperDialogState extends State<SniperDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController nameController;
  late TextEditingController bulletWeightController;
  late TextEditingController muzzleVelocityController;
  late TextEditingController ballisticCoefficientController;
  late TextEditingController moaToClickFactorController;
  late Map<int, TextEditingController> windageControllers;
  final List<int> windageBands = [500, 600, 700, 800, 900];

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.sniper?.name ?? '');
    bulletWeightController = TextEditingController(text: widget.sniper?.bulletWeight.toString() ?? '');
    muzzleVelocityController = TextEditingController(text: widget.sniper?.muzzleVelocity.toString() ?? '');
    ballisticCoefficientController = TextEditingController(text: widget.sniper?.ballisticCoefficient.toString() ?? '');
    moaToClickFactorController = TextEditingController(text: widget.sniper?.moaToClickFactor.toString() ?? '4.0');
    windageControllers = {
      for (var band in windageBands)
        band: TextEditingController(
          text: widget.sniper?.windageConstants[band]?.toString() ?? _defaultWindageConstant(band),
        ),
    };
  }

  String _defaultWindageConstant(int band) {
    switch (band) {
      case 500:
        return '13';
      case 600:
        return '12';
      case 700:
      case 800:
        return '11';
      case 900:
        return '10';
      default:
        return '13';
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    bulletWeightController.dispose();
    muzzleVelocityController.dispose();
    ballisticCoefficientController.dispose();
    moaToClickFactorController.dispose();
    for (var c in windageControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.sniper == null ? AppLocalizations.of(context)!.addSniper : AppLocalizations.of(context)!.sniperManagement),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.sniperManagement),
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.sniperManagement : null,
              ),
              TextFormField(
                controller: bulletWeightController,
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.bulletWeight),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || double.tryParse(v) == null || double.parse(v) <= 0 ? AppLocalizations.of(context)!.bulletWeight : null,
              ),
              TextFormField(
                controller: muzzleVelocityController,
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.muzzleVelocity),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || double.tryParse(v) == null || double.parse(v) <= 0 ? AppLocalizations.of(context)!.muzzleVelocity : null,
              ),
              TextFormField(
                controller: ballisticCoefficientController,
                decoration: InputDecoration(labelText: 'Ballistic Coefficient'),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || double.tryParse(v) == null || double.parse(v) <= 0 ? 'Ballistic Coefficient' : null,
              ),
              TextFormField(
                controller: moaToClickFactorController,
                decoration: InputDecoration(labelText: 'MOA to Clicks Factor'),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || double.tryParse(v) == null || double.parse(v) <= 0 ? 'MOA to Clicks Factor' : null,
              ),
              const SizedBox(height: 16),
              Text('Windage Constants (per range, meters):', style: Theme.of(context).textTheme.titleSmall),
              ...windageBands.map((band) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: TextFormField(
                  controller: windageControllers[band],
                  decoration: InputDecoration(labelText: '$band m'),
                  keyboardType: TextInputType.number,
                  validator: (v) => v == null || double.tryParse(v) == null || double.parse(v) <= 0 ? 'Constant for $band m' : null,
                ),
              )),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.close),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final windageConstants = {
                for (var band in windageBands)
                  band: double.parse(windageControllers[band]!.text),
              };
              final sniper = SniperType(
                name: nameController.text,
                bulletWeight: double.parse(bulletWeightController.text),
                muzzleVelocity: double.parse(muzzleVelocityController.text),
                ballisticCoefficient: double.parse(ballisticCoefficientController.text),
                windageConstants: windageConstants,
                moaToClickFactor: double.parse(moaToClickFactorController.text),
                rangeCorrectionClicks: {}, // Empty map for new snipers
              );
              Navigator.pop(context, sniper);
            }
          },
          child: Text(AppLocalizations.of(context)!.calculate),
        ),
      ],
    );
  }
} 