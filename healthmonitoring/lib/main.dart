// main.dart
// Starter Flutter app for Health Monitoring (MVP)
// Features included: Firebase init, Email/Password auth (signup/login),
// Dashboard listing measurements, Add Measurement form, Firestore integration.
// Notes: Add firebase_options.dart (from FlutterFire CLI) and enable required
// packages in pubspec.yaml: firebase_core, firebase_auth, cloud_firestore, cupertino_icons, intl

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// TODO: generate this with `flutterfire configure` and place in lib/firebase_options.dart
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const HealthApp());
}

class HealthApp extends StatelessWidget {
  const HealthApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health Monitor',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData) {
          return const AuthScreen();
        }
        return const DashboardScreen();
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;

  Future<void> _submit() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final email = _emailCtrl.text.trim();
      final pass = _passCtrl.text;
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: pass,
        );
      } else {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: pass,
        );
        // create a minimal user profile in Firestore
        await FirebaseFirestore.instance
            .collection('users')
            .doc(cred.user!.uid)
            .set({
              'email': email,
              'createdAt': FieldValue.serverTimestamp(),
              'role': 'patient',
            });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message ?? 'Auth error')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health Monitor - Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 18),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _submit,
                    child: Text(_isLogin ? 'Login' : 'Create account'),
                  ),
            TextButton(
              onPressed: () => setState(() => _isLogin = !_isLogin),
              child: Text(
                _isLogin
                    ? 'Create an account'
                    : 'Already have an account? Login',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                // quick anonymous sign-in for testing
                await FirebaseAuth.instance.signInAnonymously();
              },
              child: const Text('Continue as Guest (anonymous)'),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async => await FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AddMeasurementScreen()),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, ${user.email ?? 'User'}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Recent measurements',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(child: MeasurementsList(userId: user.uid)),
          ],
        ),
      ),
    );
  }
}

class MeasurementsList extends StatelessWidget {
  final String userId;
  const MeasurementsList({Key? key, required this.userId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('measurements')
        .where('patientId', isEqualTo: userId)
        .orderBy('recordedAt', descending: true)
        .limit(50);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return const Center(child: Text('No measurements yet'));

        final docs = snapshot.data!.docs;
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final d = docs[index];
            final type = d['type'] ?? 'unknown';
            final value = d['value']?.toString() ?? '-';
            final unit = d['unit'] ?? '';
            final ts = (d['recordedAt'] as Timestamp).toDate();
            return ListTile(
              title: Text('$type — $value $unit'),
              subtitle: Text(ts.toLocal().toString()),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async => await d.reference.delete(),
              ),
            );
          },
        );
      },
    );
  }
}

class AddMeasurementScreen extends StatefulWidget {
  @override
  State<AddMeasurementScreen> createState() => _AddMeasurementScreenState();
}

class _AddMeasurementScreenState extends State<AddMeasurementScreen> {
  final _formKey = GlobalKey<FormState>();
  String _type = 'blood_glucose';
  final _valueCtrl = TextEditingController();
  String _unit = 'mg/dL';
  DateTime _time = DateTime.now();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    return Scaffold(
      appBar: AppBar(title: const Text('Add Measurement')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                value: _type,
                items: const [
                  DropdownMenuItem(
                    value: 'blood_glucose',
                    child: Text('Blood glucose'),
                  ),
                  DropdownMenuItem(
                    value: 'blood_pressure',
                    child: Text('Blood pressure'),
                  ),
                  DropdownMenuItem(value: 'spo2', child: Text('SpO2')),
                  DropdownMenuItem(value: 'weight', child: Text('Weight')),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'blood_glucose'),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _valueCtrl,
                decoration: const InputDecoration(labelText: 'Value'),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (s) =>
                    (s == null || s.isEmpty) ? 'Enter a value' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: _unit,
                onChanged: (v) => _unit = v,
                decoration: const InputDecoration(
                  labelText: 'Unit (e.g. mg/dL, mmHg, %)',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Time: ${_time.toLocal().toString().substring(0, 16)}'),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _time,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(_time),
                        );
                        if (t != null) {
                          setState(
                            () => _time = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                              t.hour,
                              t.minute,
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Change'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _saving
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: () async {
                        if (!_formKey.currentState!.validate()) return;
                        setState(() => _saving = true);
                        try {
                          final doc = FirebaseFirestore.instance
                              .collection('measurements')
                              .doc();
                          await doc.set({
                            'patientId': user.uid,
                            'type': _type,
                            'value': double.parse(_valueCtrl.text),
                            'unit': _unit,
                            'recordedAt': _time.toUtc(),
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                          Navigator.pop(context);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error saving: $e')),
                          );
                        } finally {
                          setState(() => _saving = false);
                        }
                      },
                      child: const Text('Save measurement'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
