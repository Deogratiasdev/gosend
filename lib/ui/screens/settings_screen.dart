import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/security/encryption_service.dart';
import '../../core/theme/theme_service.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeService themeService;

  const SettingsScreen({super.key, required this.themeService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  EncryptionService get _encryptionService => EncryptionService.instance;
  bool _showKey = false;

  @override
  void initState() {
    super.initState();
    // Force rebuild when key changes (listening to state changes if needed)
  }

  void _showKeyDialog(BuildContext context) {
    final controller = TextEditingController(
      text: _encryptionService.isKeySet ? _encryptionService.encryptionKey : '',
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Clé de chiffrement',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Utilisée pour chiffrer les messages de broadcast sur le réseau.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: !_showKey,
                style: GoogleFonts.jetBrainsMono(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Entrez ou collez la clé ici',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setDialogState(() => _showKey = !_showKey),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final key = await _encryptionService.generateKey();
                        controller.text = key;
                        setDialogState(() {});
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Générer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                await _encryptionService.setKey(controller.text.trim());
                if (!context.mounted) return;
                Navigator.pop(context);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_encryptionService.isKeySet
                        ? '🔐 Clé définie'
                        : '🔓 Chiffrement désactivé'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _copyKey(BuildContext context) {
    if (_encryptionService.isKeySet) {
      Clipboard.setData(ClipboardData(text: _encryptionService.encryptionKey));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📋 Clé copiée !'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Paramètres',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sécurité',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: colorScheme.surface,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.key,
                      color: _encryptionService.isKeySet
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      'Clé de chiffrement',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      _encryptionService.isKeySet ? 'Activée' : 'Non définie',
                      style: TextStyle(
                        color: _encryptionService.isKeySet
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    trailing: _encryptionService.isKeySet
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.copy, size: 20),
                                tooltip: 'Copier la clé',
                                onPressed: () => _copyKey(context),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                tooltip: 'Modifier',
                                onPressed: () => _showKeyDialog(context),
                              ),
                            ],
                          )
                        : null,
                    onTap: () => _showKeyDialog(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Apparence',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: colorScheme.surface,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  _buildThemeOption(
                    context,
                    widget.themeService,
                    AppThemeMode.system,
                    'Système',
                    'Utilise le thème du système',
                    Icons.brightness_auto,
                  ),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant,
                  ),
                  _buildThemeOption(
                    context,
                    widget.themeService,
                    AppThemeMode.light,
                    'Clair',
                    'Thème clair',
                    Icons.wb_sunny,
                  ),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant,
                  ),
                  _buildThemeOption(
                    context,
                    widget.themeService,
                    AppThemeMode.dark,
                    'Sombre',
                    'Thème sombre',
                    Icons.nightlight_round,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    ThemeService themeService,
    AppThemeMode mode,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = themeService.themeMode == mode;

    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      title: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      trailing: isSelected
          ? Icon(
              Icons.check_circle,
              color: colorScheme.primary,
            )
          : null,
      onTap: () async {
        await themeService.setThemeMode(mode);
        if (context.mounted) {
          Navigator.pop(context);
        }
      },
    );
  }
}