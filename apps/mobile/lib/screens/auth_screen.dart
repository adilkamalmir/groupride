import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController(text: 'leader@groupride.local');
  final _password = TextEditingController(text: 'password123');
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF12151A), Color(0xFF1A1D23), Color(0xFF2A1A12)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 48),
              Text(
                'GroupRide',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.mist,
                      letterSpacing: -1,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Never lose a rider.',
                style: TextStyle(color: AppTheme.signalSoft, fontSize: 18),
              ),
              const SizedBox(height: 40),
              if (_register)
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
              if (_register) const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppTheme.emergency)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: Text(_register ? 'Create account' : 'Sign in'),
              ),
              TextButton(
                onPressed: () => setState(() => _register = !_register),
                child: Text(
                  _register ? 'Have an account? Sign in' : 'New here? Register',
                  style: const TextStyle(color: AppTheme.steel),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Demo: leader@groupride.local / password123',
                style: TextStyle(color: AppTheme.steel, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      if (_register) {
        await auth.register(_email.text.trim(), _password.text, _name.text.trim());
      } else {
        await auth.login(_email.text.trim(), _password.text);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
