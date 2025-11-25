import 'package:flutter/material.dart';
import 'models.dart';

class SensorDashboardPage extends StatefulWidget {
  const SensorDashboardPage({super.key});
  @override
  State<SensorDashboardPage> createState() => _SensorDashboardPageState();
}

class _SensorDashboardPageState extends State<SensorDashboardPage> {
  late final DashboardController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = DashboardController();
    ctrl.addListener(_onUpdate);
  }

  @override
  void dispose() {
    ctrl.removeListener(_onUpdate);
    ctrl.dispose();
    super.dispose();
  }

  void _onUpdate() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gateway y Sensores')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('Gateway:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                DropdownButton<Gateway>(
                  value: ctrl.selected,
                  items: ctrl.gateways
                      .map((g) => DropdownMenuItem<Gateway>(value: g, child: Text('${g.name} · ${g.location}')))
                      .toList(),
                  onChanged: (g) => setState(() => ctrl.selected = g),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () {
                    ctrl.openPairingWindow(seconds: 30);
                    _showPairOverlay(context);
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('Emparejar sensor'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Sensores asignados', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Expanded(
              child: ctrl.assigned.isEmpty
                  ? const Center(child: Text('No hay sensores asignados'))
                  : ListView.builder(
                      itemCount: ctrl.assigned.length,
                      itemBuilder: (ctx, i) {
                        final s = ctrl.assigned[i];
                        return Card(
                          child: ListTile(
                            leading: Icon(ctrl.iconFor(s.type), color: ctrl.colorFor(s.type)),
                            title: Text(s.name),
                            subtitle: Text('${s.id} · RSSI ${s.rssi}'),
                            trailing: _statusChip(s.state),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPairOverlay(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return AnimatedBuilder(
          animation: ctrl,
          builder: (ctx, _) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text('Vinculación por botón', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('Tiempo: ${ctrl.pairingSecondsLeft}s'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('Mantén presionado el botón del sensor para vincular.'),
                    const SizedBox(height: 12),
                    if (!ctrl.pairingWindowOpen)
                      const Text('Ventana cerrada', style: TextStyle(color: Colors.red))
                    else ...[
                      _pendingList(),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            ctrl.closePairingWindow();
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('Cerrar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      ctrl.closePairingWindow();
    });
  }

  Widget _pendingList() {
    if (ctrl.pending.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F8E9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('Buscando sensores cercanos…'),
      );
    }
    return SizedBox(
      height: 260,
      child: ListView.builder(
        itemCount: ctrl.pending.length,
        itemBuilder: (ctx, i) {
          final s = ctrl.pending[i];
          return Card(
            child: ListTile(
              leading: Icon(ctrl.iconFor(s.type), color: ctrl.colorFor(s.type)),
              title: Text('${s.name} · ${s.id}'),
              subtitle: Text('RSSI ${s.rssi}'),
              trailing: Wrap(spacing: 8, children: [
                TextButton(
                  onPressed: () {
                    _promptNameAndAdd(ctx, s);
                  },
                  child: const Text('Agregar'),
                ),
                TextButton(
                  onPressed: () => setState(() => ctrl.ignoreSensor(s)),
                  child: const Text('Ignorar'),
                ),
                TextButton(
                  onPressed: () => setState(() => ctrl.blockSensor(s)),
                  child: const Text('Bloquear'),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  void _promptNameAndAdd(BuildContext ctx, Sensor s) async {
    final nameCtrl = TextEditingController(text: s.name);
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Asignar sensor al gateway'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre opcional')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Agregar')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        ctrl.addSensor(s, newName: nameCtrl.text.trim());
      });
    }
  }

  Widget _statusChip(SensorState st) {
    switch (st) {
      case SensorState.assigned:
        return const Chip(label: Text('Asignado'), backgroundColor: Color(0xFFE8F5E9));
      case SensorState.offline:
        return const Chip(label: Text('Offline'), backgroundColor: Color(0xFFFFEBEE));
      case SensorState.pending:
        return const Chip(label: Text('Pendiente'));
      case SensorState.ignored:
        return const Chip(label: Text('Ignorado'));
      case SensorState.blocked:
        return const Chip(label: Text('Bloqueado'));
    }
  }
}