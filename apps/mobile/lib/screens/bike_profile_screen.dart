import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class BikeProfileScreen extends StatefulWidget {
  const BikeProfileScreen({super.key});

  @override
  State<BikeProfileScreen> createState() => _BikeProfileScreenState();
}

class _BikeProfileScreenState extends State<BikeProfileScreen> {
  final _model = TextEditingController();
  final _tank = TextEditingController();
  final _range = TextEditingController();
  final _sinceFill = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final bike = context.read<AuthService>().profile?.bike;
    if (bike != null) {
      _model.text = bike.model;
      _tank.text = bike.tankSizeLiters.toString();
      _range.text = bike.typicalRangeKm.toString();
      _sinceFill.text = (bike.distanceSinceFillKm ?? 0).toString();
    } else {
      _model.text = 'Honda CB500X';
      _tank.text = '17.7';
      _range.text = '400';
      _sinceFill.text = '0';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bike & fuel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Used to predict when the group needs fuel.',
            style: TextStyle(color: AppTheme.steel),
          ),
          const SizedBox(height: 16),
          TextField(controller: _model, decoration: const InputDecoration(labelText: 'Bike model')),
          const SizedBox(height: 12),
          TextField(
            controller: _tank,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Tank size (L)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _range,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Typical range (km)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sinceFill,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Distance since last fill (km)'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await context.read<AuthService>().updateBike(
            BikeProfile(
              model: _model.text.trim(),
              tankSizeLiters: double.parse(_tank.text),
              typicalRangeKm: double.parse(_range.text),
              distanceSinceFillKm: double.parse(_sinceFill.text),
            ),
          );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
