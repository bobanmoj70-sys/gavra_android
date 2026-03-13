import 'package:flutter/material.dart';

import '../services/v3/v3_kapacitet_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';

/// Admin ekran za podešavanje kapaciteta polazaka
class V2KapacitetScreen extends StatefulWidget {
  const V2KapacitetScreen({super.key});

  @override
  State<V2KapacitetScreen> createState() => _KapacitetScreenState();
}

class _KapacitetScreenState extends State<V2KapacitetScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final Stream<Map<String, Map<String, int>>> _streamKapacitet;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _streamKapacitet = V3KapacitetService.streamKapacitet();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _editKapacitet(String grad, String vreme, int trenutni) async {
    final result = await showDialog<int>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _KapacitetEditDialog(grad: grad, vreme: vreme, trenutni: trenutni),
    );
    if (result != null && result != trenutni) {
      final success = await V3KapacitetService.setKapacitet(grad, vreme, result);
      if (!mounted) return;
      if (success) {
        V2AppSnackBar.success(context, '✅ $grad $vreme = $result mesta');
      } else {
        V2AppSnackBar.error(context, '❌ Greška pri čuvanju');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('🎫 Kapacitet Polazaka (V3)', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.green,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: const [
              Tab(text: 'Bela Crkva'),
              Tab(text: 'Vrsac'),
            ],
          ),
        ),
        body: StreamBuilder<Map<String, Map<String, int>>>(
          stream: _streamKapacitet,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data ?? {'BC': {}, 'VS': {}};
            return TabBarView(
              controller: _tabController,
              children: [
                _kapacitetGradTab('BC', V3KapacitetService.bcVremena, data, _editKapacitet),
                _kapacitetGradTab('VS', V3KapacitetService.vsVremena, data, _editKapacitet),
              ],
            );
          },
        ),
      ),
    );
  }
}

Color _kapacitetGetBoja(int mesta) {
  if (mesta >= 8) return Colors.green;
  if (mesta >= 5) return Colors.orange;
  return Colors.red;
}

// ─── top-level tab builder ───────────────────────────────────────────────────

Widget _kapacitetGradTab(
  String grad,
  List<String> vremena,
  Map<String, Map<String, int>> kapacitet,
  Future<void> Function(String grad, String vreme, int trenutni) onEdit,
) {
  return ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: vremena.length,
    itemBuilder: (ctx, index) {
      final vreme = vremena[index];
      final maxMesta = kapacitet[grad]?[vreme] ?? 8;
      return Card(
        color: Theme.of(ctx).glassContainer,
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          title: Text(
            vreme,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            'Kapacitet: $maxMesta mesta',
            style: TextStyle(color: maxMesta < 8 ? Colors.orange : Colors.white70),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: maxMesta > 1
                    ? () async {
                        final success = await V3KapacitetService.setKapacitet(grad, vreme, maxMesta - 1);
                        if (!ctx.mounted) return;
                        if (!success) V2AppSnackBar.error(ctx, '❌ Greška pri čuvanju');
                      }
                    : null,
                icon: const Icon(Icons.remove_circle, color: Colors.red, size: 32),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _kapacitetGetBoja(maxMesta),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '$maxMesta',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton(
                onPressed: maxMesta < 20
                    ? () async {
                        final success = await V3KapacitetService.setKapacitet(grad, vreme, maxMesta + 1);
                        if (!ctx.mounted) return;
                        if (!success) V2AppSnackBar.error(ctx, '❌ Greška pri čuvanju');
                      }
                    : null,
                icon: const Icon(Icons.add_circle, color: Colors.green, size: 32),
              ),
            ],
          ),
          onTap: () => onEdit(grad, vreme, maxMesta),
        ),
      );
    },
  );
}

// ─── _KapacitetEditDialog ────────────────────────────────────────────────────

class _KapacitetEditDialog extends StatefulWidget {
  const _KapacitetEditDialog({
    required this.grad,
    required this.vreme,
    required this.trenutni,
  });
  final String grad;
  final String vreme;
  final int trenutni;

  @override
  State<_KapacitetEditDialog> createState() => _KapacitetEditDialogState();
}

class _KapacitetEditDialogState extends State<_KapacitetEditDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.trenutni.toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          gradient: Theme.of(context).backgroundGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zaglavlje
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).glassContainer,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Theme.of(context).glassBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '🎫 ${widget.grad} - ${widget.vreme}',
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            // Tijelo
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Unesite maksimalan broj mesta:',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).glassContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).glassBorder),
                    ),
                    child: TextField(
                      controller: _ctrl,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.withValues(alpha: 0.5)),
                            ),
                          ),
                          child: const Text('Otkaži', style: TextStyle(color: Colors.grey, fontSize: 16)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final value = int.tryParse(_ctrl.text);
                            if (value != null && value > 0 && value <= 20) {
                              Navigator.pop(context, value);
                            } else {
                              V2AppSnackBar.error(context, 'Unesite broj između 1 i 20');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Sačuvaj', style: TextStyle(fontSize: 16, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
