import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';

class RightPanel extends StatefulWidget {
  final String localIP;
  final bool isServerRunning;
  final VoidCallback onToggleServer;
  final VoidCallback onRefreshIP;
  final String? connectedDeviceName;
  final String? connectedDeviceIP;

  const RightPanel({
    required this.localIP,
    required this.isServerRunning,
    required this.onToggleServer,
    required this.onRefreshIP,
    this.connectedDeviceName,
    this.connectedDeviceIP,
  });

  @override
  State<RightPanel> createState() => _RightPanelState();
}

class _RightPanelState extends State<RightPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _serverAnimationController;

  @override
  void initState() {
    super.initState();
    _serverAnimationController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _serverAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accentGreen = Color(0xFF336B4E);
    const bgDark = Color(0xFF0D0D0D);
    const textSecondary = Color(0xFFCCCCCC);

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: bgDark,
        border: Border(
          left: BorderSide(
            color: accentGreen.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              'Panneau Serveur',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),

            // Server Status Card
            _buildServerCard(accentGreen, bgDark, textSecondary),
            const SizedBox(height: 20),

            // Local IP Section
            _buildIPSection(accentGreen, bgDark, textSecondary),
            const SizedBox(height: 20),

            // Connected Device Section
            if (widget.connectedDeviceName != null)
              _buildConnectedDeviceSection(accentGreen, bgDark, textSecondary),

            // Server Stats
            const SizedBox(height: 20),
            _buildStatsSection(accentGreen, bgDark, textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildServerCard(Color accentGreen, Color bgDark, Color textSecondary) {
    return GestureDetector(
      onTap: widget.onToggleServer,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.isServerRunning
              ? accentGreen.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isServerRunning
                ? accentGreen.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.isServerRunning)
                  AnimatedBuilder(
                    animation: _serverAnimationController,
                    builder: (context, child) {
                      return Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: accentGreen.withValues(
                            alpha: 0.5 +
                                (_serverAnimationController.value * 0.5),
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  accentGreen.withValues(alpha: 0.5),
                              blurRadius: 8,
                            )
                          ],
                        ),
                      );
                    },
                  )
                else
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  widget.isServerRunning
                      ? 'Serveur Actif'
                      : 'Serveur Arrêté',
                  style: GoogleFonts.inter(
                    color: widget.isServerRunning ? accentGreen : textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  widget.isServerRunning
                      ? 'Cliquer pour arrêter'
                      : 'Cliquer pour démarrer',
                  style: GoogleFonts.inter(
                    color: textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIPSection(Color accentGreen, Color bgDark, Color textSecondary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentGreen.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Adresse IP Locale',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: accentGreen.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.localIP,
                        style: GoogleFonts.inconsolata(
                          color: accentGreen,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Port: 9090',
                        style: GoogleFonts.inter(
                          color: textSecondary.withValues(alpha: 0.6),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: widget.onRefreshIP,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.refresh_rounded,
                      color: accentGreen,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _copyIPButton(accentGreen),
        ],
      ),
    );
  }

  Widget _copyIPButton(Color accentGreen) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          // Copier l'IP au presse-papiers
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('IP copiée'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        icon: const Icon(Icons.copy_rounded, size: 16),
        label: Text(
          'Copier l\'IP',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: accentGreen.withValues(alpha: 0.2),
          foregroundColor: accentGreen,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectedDeviceSection(
    Color accentGreen,
    Color bgDark,
    Color textSecondary,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentGreen.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.devices_other_rounded,
                color: accentGreen,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Appareil Connecté',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.connectedDeviceName ?? 'N/A',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.connectedDeviceIP ?? 'N/A',
                  style: GoogleFonts.inconsolata(
                    color: accentGreen,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(Color accentGreen, Color bgDark, Color textSecondary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Statistiques',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildStatItem('Transferts', '0', accentGreen),
          const SizedBox(height: 8),
          _buildStatItem('Fichiers', '0', accentGreen),
          const SizedBox(height: 8),
          _buildStatItem('Vitesse', '0 MB/s', accentGreen),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color accentGreen) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: const Color(0xFFCCCCCC),
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: accentGreen,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
