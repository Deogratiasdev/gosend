import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme_service.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeService themeService;
  final String? receiveDirectoryPath;
  final VoidCallback? onOpenReceiveDirectory;

  const SettingsScreen({
    super.key,
    required this.themeService,
    this.receiveDirectoryPath,
    this.onOpenReceiveDirectory,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ─────────────── Build ───────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Paramètres', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 20)),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Dossier de réception ──
                _sectionTitle(colorScheme, 'Stockage'),
                const SizedBox(height: 12),
                _card(colorScheme, ListTile(
                  leading: Icon(Icons.folder_open_rounded, color: colorScheme.secondary),
                  title: Text('Dossier de réception', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500)),
                  subtitle: widget.receiveDirectoryPath != null
                      ? Text(widget.receiveDirectoryPath!, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontFamily: 'monospace'), maxLines: 2, overflow: TextOverflow.ellipsis)
                      : Text('Non disponible', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
                  trailing: widget.onOpenReceiveDirectory != null
                      ? Icon(Icons.open_in_new, size: 18, color: colorScheme.onSurfaceVariant)
                      : null,
                  onTap: widget.onOpenReceiveDirectory,
                )),

                const SizedBox(height: 28),

                // ── Apparence ──
                _sectionTitle(colorScheme, 'Apparence'),
                const SizedBox(height: 12),
                _card(colorScheme, Column(
                  children: [
                    _themeOption(context, AppThemeMode.system, 'Système', 'Thème du système', Icons.brightness_auto),
                    Divider(height: 1, color: colorScheme.outlineVariant),
                    _themeOption(context, AppThemeMode.light, 'Clair', 'Thème clair', Icons.wb_sunny),
                    Divider(height: 1, color: colorScheme.outlineVariant),
                    _themeOption(context, AppThemeMode.dark, 'Sombre', 'Thème sombre', Icons.nightlight_round),
                  ],
                )),

                const SizedBox(height: 28),

                // ── À propos ──
                _sectionTitle(colorScheme, 'À propos'),
                const SizedBox(height: 12),
                _card(colorScheme, Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                            child: Icon(Icons.send_rounded, size: 24, color: colorScheme.primary),
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('GoSend', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800)),
                              Text('P2P File Transfer Pro', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                            ],
                          )),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Divider(height: 1, color: colorScheme.outlineVariant),
                      const SizedBox(height: 16),
                      _aboutRow(Icons.person_outline, 'Développeur', 'HOUNNOU Déo-Gratias', colorScheme),
                      const SizedBox(height: 12),
                      _aboutRow(Icons.cake_outlined, 'Né en', '2007', colorScheme),
                      const SizedBox(height: 12),
                      _aboutRow(Icons.event_available, 'Finalisé le', 'Lundi 6 juillet 2026', colorScheme),
                      const SizedBox(height: 12),
                      _aboutRow(Icons.language, 'Portfolio', 'deo-gratias.pages.dev', colorScheme),
                    ],
                  ),
                )),

                const SizedBox(height: 24),
              ],
            ),
          ),
        );
  }

  // ─────────────── Helpers UI ───────────────

  Widget _sectionTitle(ColorScheme c, String text) => Text(
    text,
    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: c.onSurfaceVariant),
  );

  Widget _card(ColorScheme c, Widget child) => Card(
    color: c.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.outlineVariant)),
    child: child,
  );

  Widget _themeOption(BuildContext context, AppThemeMode mode, String title, String subtitle, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = widget.themeService.themeMode == mode;
    return ListTile(
      leading: Icon(icon, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant),
      title: Text(title, style: GoogleFonts.plusJakartaSans(fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, color: isSelected ? colorScheme.primary : colorScheme.onSurface)),
      subtitle: Text(subtitle, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
      trailing: isSelected ? Icon(Icons.check_circle, color: colorScheme.primary) : null,
      onTap: () async { await widget.themeService.setThemeMode(mode); setState(() {}); },
    );
  }

  Widget _aboutRow(IconData icon, String label, String value, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
            Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
          ],
        )),
      ],
    );
  }
}
