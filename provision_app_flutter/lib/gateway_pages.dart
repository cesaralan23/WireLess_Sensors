import 'package:flutter/material.dart';
import 'models.dart';
import 'gateway_provision_wizard.dart';

class GatewaysPage extends StatefulWidget {
  const GatewaysPage({super.key});
  @override
  State<GatewaysPage> createState() => _GatewaysPageState();
}

class _GatewaysPageState extends State<GatewaysPage> {
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
      appBar: AppBar(title: const Text('Gateways')),
      body: ListView.builder(
        itemCount: ctrl.gateways.length,
        itemBuilder: (ctx, i) {
          final g = ctrl.gateways[i];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.router),
              title: Text(g.name),
              subtitle: Text(g.location),
              onTap: () {
                ctrl.selected = g;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GatewayDetailPage(ctrl: ctrl, gateway: g),
                  ),
                );
              },
              trailing: IconButton(
                tooltip: 'Eliminar gateway',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  _deleteGateway(g);
                },
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addGateway,
        icon: const Icon(Icons.add),
        label: const Text('Agregar gateway'),
      ),
    );
  }

  Future<void> _addGateway() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddGatewayWizard(controller: ctrl)),
    );
    if (ok == true) {
      setState(() {});
    }
  }

  void _deleteGateway(Gateway g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Eliminar gateway'),
        content: Text('¿Seguro deseas eliminar "${g.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        ctrl.removeGateway(g.id);
      });
    }
  }
}

class GatewayDetailPage extends StatefulWidget {
  final DashboardController ctrl;
  final Gateway gateway;
  const GatewayDetailPage({super.key, required this.ctrl, required this.gateway});
  @override
  State<GatewayDetailPage> createState() => _GatewayDetailPageState();
}

class _GatewayDetailPageState extends State<GatewayDetailPage> {
  DashboardController get ctrl => widget.ctrl;

  @override
  void initState() {
    super.initState();
    ctrl.addListener(_onUpdate);
  }

  @override
  void dispose() {
    ctrl.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.gateway.name)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
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
            const Text('Sensores', style: TextStyle(fontWeight: FontWeight.w600)),
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
                            subtitle: Text(s.lastSeen != null ? 'Último: ${s.lastSeen}' : ''),
                            // ID oculto: mostrar en pantalla de detalle/diálogo
                            trailing: Wrap(spacing: 6, children: [
                              TextButton(onPressed: () => _viewSensor(s), child: const Text('Ver')),
                              TextButton(onPressed: () => _editSensor(s), child: const Text('Editar')),
                              TextButton(onPressed: () => _deleteSensor(s), child: const Text('Borrar')),
                            ]),
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
              title: Text(s.name),
              subtitle: Text('ID ${s.id}'),
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

  void _viewSensor(Sensor s) {
    final data = ctrl.sampleDataFor(s);
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(s.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${s.id}'),
            const SizedBox(height: 8),
            for (final e in data.entries) Text('${e.key}: ${e.value}'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('Cerrar'))],
      ),
    );
  }

  void _editSensor(Sensor s) async {
    final nameCtrl = TextEditingController(text: s.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Editar sensor'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        ctrl.updateSensorName(s, nameCtrl.text.trim());
      });
    }
  }

  void _deleteSensor(Sensor s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Eliminar sensor'),
        content: Text('¿Seguro deseas eliminar "${s.name}" del gateway?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        ctrl.deleteSensor(s);
      });
    }
  }
}