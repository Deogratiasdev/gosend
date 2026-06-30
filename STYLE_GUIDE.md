# Guide de Style - GoSend

## Palette de Couleurs

```dart
static const Color _accentGreen = Color(0xFF336B4E);
static const Color _accentHover = Color(0xFF4A8A6E);
static const Color _bgDark = Color(0xFF0D0D0D);
static const Color _textSecondary = Color(0xFFCCCCCC);
```

**Utilisation:**
- `_accentGreen`: Couleur principale pour les accents, icônes, textes mis en évidence
- `_accentHover`: Couleur pour les états hover/actifs
- `_bgDark`: Fond principal de l'application
- `_textSecondary`: Texte secondaire, descriptions
- `Colors.white`: Texte principal, titres

## Typographie

**Import requis:**
```dart
import 'package:google_fonts/google_fonts.dart';
```

### Titres Principaux
```dart
GoogleFonts.outfit(
  fontSize: 22, // Responsive: 20 si h<700, 24 si h>900
  fontWeight: FontWeight.w900,
  color: Colors.white,
  letterSpacing: -1.0,
  height: 1.1,
)
```

### Sous-titres
```dart
GoogleFonts.outfit(
  color: _textSecondary,
  fontSize: 12,
  fontWeight: FontWeight.w400,
  letterSpacing: 0.2,
)
```

### Titres de Section
```dart
GoogleFonts.outfit(
  color: Colors.white,
  fontSize: 18,
  fontWeight: FontWeight.w800,
  letterSpacing: -0.5,
)
```

### Titres d'Items
```dart
GoogleFonts.outfit(
  color: Colors.white,
  fontSize: 16,
  fontWeight: FontWeight.w700,
  letterSpacing: -0.2,
)
```

### Descriptions
```dart
GoogleFonts.outfit(
  color: _textSecondary,
  fontSize: 14,
  height: 1.5,
  fontWeight: FontWeight.w400,
)
```

## Responsive Design

### Padding Horizontal
```dart
final sh = MediaQuery.of(context).size.height;
final pad = sh < 700 ? 16.0 : sh > 900 ? 24.0 : 20.0;
```

### Espacements Verticaux
- `SizedBox(height: sh * 0.03)` - Espace après le header
- `SizedBox(height: sh * 0.025)` - Espace entre header et contenu
- `SizedBox(height: 16)` - Entre les items
- `SizedBox(height: 30)` - Entre les sections
- `SizedBox(height: 40)` - Avant le footer

## Animations

### AnimationController Setup
```dart
late final AnimationController _headerController;
late final AnimationController _contentController;

@override
void initState() {
  super.initState();
  _headerController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  _contentController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  _startAnimations();
}

void _startAnimations() async {
  await Future.delayed(const Duration(milliseconds: 150));
  _headerController.forward();
  await Future.delayed(const Duration(milliseconds: 300));
  _contentController.forward();
}

@override
void dispose() {
  _headerController.dispose();
  _contentController.dispose();
  super.dispose();
}
```

### Fade Animation
```dart
late Animation<double> _headerFade;
_headerFade = CurvedAnimation(
  parent: _headerController,
  curve: Curves.easeOut,
);

// Utilisation
FadeTransition(
  opacity: _headerFade,
  child: Widget(),
)
```

### Slide Animation
```dart
late Animation<Offset> _headerSlide;
_headerSlide = Tween<Offset>(
  begin: const Offset(0, -0.3),
  end: Offset.zero,
).animate(
  CurvedAnimation(
    parent: _headerController,
    curve: Curves.easeOutCubic,
  ),
);

// Utilisation
SlideTransition(
  position: _headerSlide,
  child: Widget(),
)
```

## Structure de Page

### Template de Base
```dart
@override
Widget build(BuildContext context) {
  final sh = MediaQuery.of(context).size.height;
  final pad = sh < 700 ? 16.0 : sh > 900 ? 24.0 : 20.0;

  return Scaffold(
    backgroundColor: _bgDark,
    body: SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: sh * 0.03),
            // Header avec animations
            SizedBox(height: sh * 0.025),
            Expanded(
              child: // Contenu scrollable
            ),
          ],
        ),
      ),
    ),
  );
}
```

### Scrollable Content
```dart
SingleChildScrollView(
  physics: const BouncingScrollPhysics(),
  child: Column(
    children: [
      // Contenu
    ],
  ),
)
```

## Composants

### Bouton Retour Animé
```dart
class _BackBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _BackBtn({required this.onTap});

  @override
  State<_BackBtn> createState() => _BackBtnState();
}

class _BackBtnState extends State<_BackBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.0,
      upperBound: 0.04,
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
```

### Item avec Icône
```dart
Widget _privacyItem(IconData icon, String title, String desc) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _accentGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _accentGreen, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Text(
            desc,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    ),
  );
}
```

### Diviseur
```dart
Widget _divider() => Center(
  child: Container(
    width: 60,
    height: 1,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(1),
      color: Colors.white.withValues(alpha: 0.1),
    ),
  ),
);
```

### Footer
```dart
Widget _footer() {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 2,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            gradient: LinearGradient(
              colors: [
                _accentGreen.withValues(alpha: 0.3),
                _accentHover.withValues(alpha: 0.2),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Dernière mise à jour: Mars 2026',
          style: GoogleFonts.outfit(
            color: _textSecondary.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.8,
          ),
        ),
      ],
    ),
  );
}
```

## Patterns de Texte

### Texte avec Accent
```dart
RichText(
  text: TextSpan(
    style: TextStyle(
      fontSize: fs,
      fontWeight: FontWeight.w900,
      color: Colors.white,
      letterSpacing: -1.0,
      height: 1.1,
    ),
    children: const [
      TextSpan(text: 'Règles de '),
      TextSpan(
        text: 'confidentialité',
        style: TextStyle(color: _accentGreen),
      ),
    ],
  ),
)
```

## Icônes Recommandées

Utiliser les `Icons` de Material avec le suffixe `_rounded`:
- `Icons.arrow_back_rounded`
- `Icons.security_rounded`
- `Icons.enhanced_encryption_rounded`
- `Icons.visibility_off_rounded`
- `Icons.person_rounded`
- `Icons.message_rounded`
- `Icons.settings_rounded`
- `Icons.hub_rounded`
- `Icons.support_agent_rounded`
- `Icons.security_update_good_rounded`
- `Icons.download_rounded`
- `Icons.delete_rounded`
- `Icons.gpp_good_rounded`
- `Icons.business_rounded`
- `Icons.admin_panel_settings_rounded`
- `Icons.groups_rounded`
- `Icons.email_rounded`
- `Icons.update_rounded`

## Structure de Projet

```
lib/
├── screens/
│   └── [screen_name]_screen.dart
```

## Conventions de Nommage

- **Classes**: `PascalCase` (ex: `PrivacyScreen`)
- **Widgets privés**: `_camelCase` (ex: `_BackBtn`, `_buildTitle`)
- **Méthodes**: `_camelCase` pour les méthodes privées
- **Variables**: `_camelCase` pour les variables privées
- **Constantes**: `_camelCase` pour les constantes privées

## Mixins Requis

Pour les animations:
- `with TickerProviderStateMixin` pour les widgets avec AnimationController
- `with SingleTickerProviderStateMixin` pour les widgets simples avec une seule animation

## Transparence et Alpha

Utiliser `withValues(alpha: x)` au lieu de `withOpacity()`:
```dart
_accentOrange.withValues(alpha: 0.12)
Colors.white.withValues(alpha: 0.1)
```

## Bordures et Coins Arrondis

```dart
BorderRadius.circular(12) // Pour les boutons/containers
BorderRadius.circular(1)  // Pour les petits éléments (diviseurs)
```

## Gradients

```dart
LinearGradient(
  colors: [
    _accentOrange.withValues(alpha: 0.3),
    _accentHover.withValues(alpha: 0.2),
  ],
)
```

## Import Standard

```dart
import 'package:flutter/material.dart';
```

## Checklist pour Nouvelle Page

- [ ] Définir les constantes de couleur
- [ ] Créer les AnimationControllers dans initState
- [ ] Implémenter dispose pour nettoyer les contrôleurs
- [ ] Ajouter le responsive design avec MediaQuery
- [ ] Utiliser SafeArea et Padding
- [ ] Implémenter les animations (fade/slide)
- [ ] Utiliser BouncingScrollPhysics pour le scroll
- [ ] Suivre les conventions de typographie
- [ ] Utiliser les icônes _rounded
- [ ] Tester sur différentes tailles d'écran
