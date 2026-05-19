import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseTestScreen extends StatefulWidget {
  const FirebaseTestScreen({super.key});

  @override
  State<FirebaseTestScreen> createState() => _FirebaseTestScreenState();
}

class _FirebaseTestScreenState extends State<FirebaseTestScreen> {
  final List<_TestResult> _results = [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _runTests();
  }

  Future<void> _runTests() async {
    setState(() {
      _results.clear();
      _running = true;
    });

    await _test('Firebase Core inicializado', () async {
      final app = Firebase.app();
      return 'Proyecto: ${app.options.projectId}';
    });

    await _test('Firebase Auth disponible', () async {
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser;
      return user == null
          ? 'Sin sesión activa (correcto para primera vez)'
          : 'Sesión activa: ${user.uid}';
    });

    await _test('Firestore — escritura de prueba', () async {
      final doc = FirebaseFirestore.instance
          .collection('_test')
          .doc('ping');
      await doc.set({
        'timestamp': FieldValue.serverTimestamp(),
        'message': 'TecNM Chat conectado',
      });
      return 'Documento escrito correctamente';
    });

    await _test('Firestore — lectura de prueba', () async {
      final doc = await FirebaseFirestore.instance
          .collection('_test')
          .doc('ping')
          .get();
      final data = doc.data();
      return 'Leído: ${data?['message']}';
    });

    await _test('Firestore — borrado de prueba', () async {
      await FirebaseFirestore.instance
          .collection('_test')
          .doc('ping')
          .delete();
      return 'Documento de prueba eliminado';
    });

    setState(() => _running = false);
  }

  Future<void> _test(String name, Future<String> Function() fn) async {
    try {
      final detail = await fn();
      setState(() => _results.add(_TestResult(name, true, detail)));
    } catch (e) {
      setState(() => _results.add(_TestResult(name, false, e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final passed = _results.where((r) => r.ok).length;
    final total = _results.length;
    final allDone = !_running && total == 5;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico Firebase'),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        actions: [
          if (!_running)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _runTests,
            ),
        ],
      ),
      body: Column(
        children: [
          // Resumen
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: allDone
                ? (passed == total ? const Color(0xFF25D366) : Colors.orange)
                : const Color(0xFF128C7E),
            child: Column(
              children: [
                if (_running)
                  const CircularProgressIndicator(color: Colors.white)
                else
                  Icon(
                    passed == total ? Icons.check_circle : Icons.warning,
                    color: Colors.white,
                    size: 48,
                  ),
                const SizedBox(height: 8),
                Text(
                  _running
                      ? 'Probando conexión...'
                      : '$passed / $total pruebas exitosas',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Proyecto: tarea6-clon',
                  style: TextStyle(color: Colors.white.withOpacity(0.85)),
                ),
              ],
            ),
          ),

          // Lista de resultados
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = _results[i];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: r.ok
                        ? const Color(0xFF25D366)
                        : Colors.red.shade400,
                    child: Icon(
                      r.ok ? Icons.check : Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  title: Text(
                    r.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    r.detail,
                    style: TextStyle(
                      color: r.ok ? Colors.grey[600] : Colors.red[700],
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ),

          // Indicador final
          if (allDone)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: passed == total
                  ? const Color(0xFFDCF8C6)
                  : Colors.orange.shade50,
              child: Text(
                passed == total
                    ? 'Firebase conectado correctamente. La app esta lista para continuar.'
                    : 'Algunas pruebas fallaron. Revisa las reglas de Firestore o la configuracion de autenticacion.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: passed == total
                      ? const Color(0xFF075E54)
                      : Colors.orange[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TestResult {
  final String name;
  final bool ok;
  final String detail;
  const _TestResult(this.name, this.ok, this.detail);
}
