import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bantuan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader(
            icon: Icons.battery_alert,
            title: 'Agar Lokasi Tetap Aktif di Background',
          ),
          const SizedBox(height: 8),
          const Text(
            'Beberapa HP Android membatasi aplikasi berjalan di background. '
            'Agar ShareLiveLoc tetap mengirim lokasi saat aplikasi di-minimize, '
            'ikuti langkah berikut sesuai merk HP Anda:',
          ),
          const SizedBox(height: 16),
          _BrandCard(
            brand: 'Xiaomi / Redmi / POCO (MIUI / HyperOS)',
            steps: const [
              'Buka Settings / Pengaturan',
              'Pilih Apps / Aplikasi > Manage apps',
              'Cari dan pilih ShareLiveLoc',
              'Aktifkan Autostart',
              'Tap Battery saver > pilih No restrictions',
            ],
          ),
          const SizedBox(height: 12),
          _BrandCard(
            brand: 'Samsung (One UI)',
            steps: const [
              'Buka Settings / Pengaturan',
              'Pilih Apps > ShareLiveLoc',
              'Tap Battery > pilih Unrestricted',
            ],
          ),
          const SizedBox(height: 12),
          _BrandCard(
            brand: 'Oppo / Realme (ColorOS)',
            steps: const [
              'Buka Settings / Pengaturan',
              'Pilih Battery / Baterai > More settings',
              'Optimize battery usage > ShareLiveLoc > Don\'t optimize',
              'Kembali ke Apps > ShareLiveLoc > Auto-launch > Allow',
            ],
          ),
          const SizedBox(height: 12),
          _BrandCard(
            brand: 'Vivo (Funtouch OS)',
            steps: const [
              'Buka Settings / Pengaturan',
              'Pilih Battery > Background power consumption',
              'Aktifkan ShareLiveLoc',
            ],
          ),
          const SizedBox(height: 12),
          _BrandCard(
            brand: 'Android Lainnya',
            steps: const [
              'Buka Settings / Pengaturan',
              'Pilih Apps > ShareLiveLoc',
              'Tap Battery > pilih Unrestricted / No restrictions',
            ],
          ),
          const SizedBox(height: 24),
          const _SectionHeader(
            icon: Icons.settings_suggest,
            title: 'Buka Pengaturan Battery Otomatis',
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap tombol di bawah untuk langsung membuka pengaturan battery optimization.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => openAppSettings(),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Buka Pengaturan Aplikasi'),
          ),
          const SizedBox(height: 24),
          const _SectionHeader(
            icon: Icons.notifications_active,
            title: 'Notifikasi',
          ),
          const SizedBox(height: 8),
          const Text(
            'Saat berbagi lokasi aktif, akan muncul notifikasi di status bar. '
            'Notifikasi ini diperlukan agar Android tidak menghentikan proses '
            'pengiriman lokasi di background. Jangan matikan notifikasi ini.',
          ),
          const SizedBox(height: 24),
          const _SectionHeader(
            icon: Icons.info_outline,
            title: 'Tips',
          ),
          const SizedBox(height: 8),
          const _TipItem(text: 'Pastikan GPS / Lokasi aktif di HP Anda'),
          const _TipItem(text: 'Pastikan koneksi internet stabil'),
          const _TipItem(
            text: 'Jangan force close aplikasi saat sedang berbagi lokasi',
          ),
          const _TipItem(
            text:
                'Jika lokasi berhenti terupdate, buka aplikasi kembali dan cek status sharing',
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          const _SectionHeader(
            icon: Icons.person,
            title: 'Pengembang',
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'David Suwandi',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.email, size: 18, color: Colors.grey),
                      SizedBox(width: 8),
                      Text('davidsuwandi@gmail.com'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Icon(Icons.phone, size: 18, color: Colors.grey),
                      SizedBox(width: 8),
                      Text('+6285959584514'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Hubungi pengembang jika ingin membuat aplikasi serupa ataupun aplikasi lainnya.',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _TrakteerCard(username: 'david_suwandi'),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _TrakteerCard extends StatelessWidget {
  final String username;
  const _TrakteerCard({required this.username});

  @override
  Widget build(BuildContext context) {
    final url = 'https://trakteer.id/$username';
    return Card(
      elevation: 0,
      color: const Color(0xFFFFF3E0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.favorite, color: Colors.orange, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dukung Pengembang',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'trakteer.id/$username',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new,
                color: Colors.orange.shade900,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class _BrandCard extends StatelessWidget {
  final String brand;
  final List<String> steps;

  const _BrandCard({required this.brand, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              brand,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            ...steps.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.key + 1}. ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Expanded(child: Text(e.value)),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _TipItem extends StatelessWidget {
  final String text;

  const _TipItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('  \u2022  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
