import 'package:flutter/material.dart';

class WifiControls extends StatelessWidget {
  final bool canWifiScan;
  final bool wifiScanning;
  final VoidCallback onScanWifi;
  const WifiControls({
    super.key,
    required this.canWifiScan,
    required this.wifiScanning,
    required this.onScanWifi,
  });
  @override
  Widget build(BuildContext context) {
    final bool enabled = canWifiScan && !wifiScanning;
    return Row(
      children: [
        IconButton(
          onPressed: enabled ? onScanWifi : null,
          tooltip: wifiScanning ? 'Buscando redes…' : 'Buscar redes Wi‑Fi',
          icon: const Icon(Icons.wifi_find),
        ),
      ],
    );
  }
}

class CredentialsForm extends StatelessWidget {
  final TextEditingController ssidCtrl;
  final TextEditingController passCtrl;
  final FocusNode ssidFocus;
  final FocusNode passFocus;
  final bool passEnabled;
  final bool showPass;
  final bool applyBusy;
  final bool isConnected;
  final VoidCallback onToggleShowPass;
  final Future<void> Function() onApply;
  final Color? applyColor;
  const CredentialsForm({
    super.key,
    required this.ssidCtrl,
    required this.passCtrl,
    required this.ssidFocus,
    required this.passFocus,
    required this.passEnabled,
    required this.showPass,
    required this.applyBusy,
    required this.isConnected,
    required this.onToggleShowPass,
    required this.onApply,
    this.applyColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: ssidCtrl,
          focusNode: ssidFocus,
          decoration: const InputDecoration(labelText: 'SSID'),
        ),
        TextField(
          controller: passCtrl,
          focusNode: passFocus,
          enabled: passEnabled,
          decoration: InputDecoration(
            labelText: 'Password',
            helperText: passEnabled ? null : 'Red abierta: no requiere contraseña',
            suffixIcon: IconButton(
              icon: Icon(showPass ? Icons.visibility_off : Icons.visibility),
              onPressed: onToggleShowPass,
            ),
          ),
          obscureText: !showPass,
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: (isConnected && ssidCtrl.text.isNotEmpty && !applyBusy)
              ? () async {
                  await onApply();
                }
              : null,
          style: ElevatedButton.styleFrom(backgroundColor: applyColor),
          child: applyBusy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Aplicar credenciales'),
        ),
      ],
    );
  }
}