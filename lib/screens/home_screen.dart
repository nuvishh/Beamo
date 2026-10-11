import 'package:flutter/material.dart';

import '../services/network_service.dart';
import 'receive_screen.dart';
import 'send_screen.dart';

/// Entry screen: choose a role. TV users pick "Receive files".
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController(text: 'My Phone');
  String? _ip;

  @override
  void initState() {
    super.initState();
    NetworkService.getLocalIp().then((ip) {
      if (mounted) setState(() => _ip = ip);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _deviceName {
    final t = _nameController.text.trim();
    return t.isEmpty ? NetworkService.defaultDeviceName() : t;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📡 Beamo')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Share files over local Wi-Fi.\nNo internet, no cloud, no account.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Device name (shown to others)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.devices),
            ),
          ),
          const SizedBox(height: 24),
          _RoleCard(
            icon: Icons.upload_rounded,
            title: 'Send files',
            subtitle: 'Pick files and send to a nearby device',
            autofocus: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SendScreen(deviceName: _deviceName),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _RoleCard(
            icon: Icons.download_rounded,
            title: 'Receive files',
            subtitle: 'Make this device discoverable (use on TV)',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReceiveScreen(deviceName: _deviceName),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              const Icon(Icons.wifi, size: 18),
              const SizedBox(width: 8),
              Text(
                _ip == null
                    ? 'Wi-Fi IP: detecting…'
                    : 'Wi-Fi IP: $_ip  ·  port 8080',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          if (_ip == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Connect to the same Wi-Fi / hotspot as the other device.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool autofocus;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        autofocus: autofocus,
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(icon, size: 40),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios),
            ],
          ),
        ),
      ),
    );
  }
}
