# Prompt pour IA - Correction des bugs de transfert de fichiers GoSend

## Contexte
Je développe une application Flutter de transfert de fichiers P2P (GoSend) utilisant WebRTC. J'ai plusieurs bugs critiques à corriger.

## Problèmes identifiés

### 1. Réception partielle (CRITIQUE)
**Symptôme :** Le récepteur ne reçoit que 2 Mo d'une vidéo de 720 Mo au lieu de la totalité.

**Logs du récepteur :**
```
📥 Données reçues: 262144 bytes
📥 Progression: 0.1%
📥 Progression: 0.2%
...
📥 Progression: 0.4%
```
Puis ça s'arrête, le transfert ne continue pas.

**Fichiers concernés :**
- `lib/core/transfer/file_receiver.dart` - Logique de réception
- `lib/ui/screens/home_screen.dart` - Gestion des données reçues

### 2. Problème de synchronisation émetteur/récepteur
**Symptôme :** L'émetteur envoie les données mais le récepteur ne suit pas le rythme.

**Hypothèses :**
- Le DataChannel se ferme prématurément
- Les chunks sont trop volumineux pour le buffer
- Problème de gestion du flux binaire

### 3. Saturation mémoire (RAM)
**Symptôme :** Pour un fichier de 720 Mo, l'application utilise 2x la RAM (1.4 Go) car on copie les données inutilement.

**Code problématique :**
```dart
Uint8List.fromList(chunk) // Crée une copie en mémoire
```

**Fichier concerné :**
- `lib/core/transfer/optimized_transfer_manager.dart`

### 4. Sélecteur de fichiers mobile
**Demande :** Sur Android, proposer un choix entre :
- Photos/Vidéos (via ImagePicker)
- Fichiers (via FilePicker)

**Fichier concerné :**
- `lib/ui/screens/home_screen.dart` - méthode `_pickFiles()`

## Architecture actuelle

### Émetteur (Sender)
1. `OptimizedTransferManager.sendFile()` - Lit le fichier et envoie via WebRTC
2. `WebRTCService` - Gère la connexion WebRTC et le DataChannel
3. Envoi par chunks de 256 KB à 2 MB (adaptatif)

### Récepteur (Receiver)
1. `WebRTCService.onMessage` - Reçoit les messages binaires
2. `FileReceiver.receiveChunk()` - Écrit les chunks dans un fichier
3. `home_screen._handleDataReceived()` - Gère la progression

### Flux de données
```
Émetteur: File → Stream → Chunks → DataChannel → Réseau
Récepteur: Réseau → DataChannel → Chunks → File
```

## Corrections déjà effectuées

### ✅ maxRetransmits augmenté
```dart
// webrtc_service.dart ligne 197
..maxRetransmits = 1000000; // Au lieu de 30
```

### ✅ Logs de débogage ajoutés
- Logs dans `webrtc_service.dart` pour tracer les messages
- Logs dans `home_screen.dart` pour tracer la réception

### ✅ Affichage progression amélioré
- Affichage en MB : "0.0 / 687.8 MB (0.1%)"

## Tâches à accomplir

### Priorité 1 - CRITIQUE : Corriger la réception partielle
**Objectif :** Le récepteur doit recevoir 100% du fichier, pas seulement 2 Mo.

**Actions :**
1. Vérifier pourquoi `_handleDataReceived` s'arrête après 2 Mo
2. Vérifier si le DataChannel se ferme prématurément
3. Vérifier la logique de `FileReceiver.receiveChunk()`
4. Ajouter des logs pour tracer chaque chunk reçu
5. S'assurer que la boucle de réception continue jusqu'à la fin du fichier

### Priorité 2 - CRITIQUE : Optimiser la mémoire
**Objectif :** Éviter la copie des chunks en mémoire.

**Actions :**
1. Utiliser `file.openRead()` pour streamer le fichier
2. Éviter `Uint8List.fromList()` qui crée des copies
3. Utiliser des vues (`Uint8List.sublistView`) si possible
4. Tester avec un fichier de 1 Go pour vérifier la RAM utilisée

### Priorité 3 - MOYENNE : Améliorer la synchronisation
**Objectif :** L'émetteur et le récepteur doivent être synchronisés.

**Actions :**
1. Ajouter un système de accusés de réception (ACK)
2. Implémenter un contrôle de flux (flow control)
3. Gérer les pertes de paquets
4. Ajouter un timeout et retry

### Priorité 4 - BASSE : Sélecteur mobile
**Objectif :** Proposer un choix entre Photos/Vidéos et Fichiers.

**Actions :**
1. Afficher un bottom sheet avec 2 options
2. Si "Photos/Vidéos" → ImagePicker().pickMultipleMedia()
3. Si "Fichiers" → FilePicker.platform.pickFiles()

## Fichiers à modifier

1. `lib/core/transfer/file_receiver.dart` - Logique de réception
2. `lib/core/transfer/optimized_transfer_manager.dart` - Optimisation mémoire
3. `lib/core/network/webrtc_service.dart` - Gestion DataChannel
4. `lib/ui/screens/home_screen.dart` - Interface et sélecteur

## Contraintes

- **Débit :** Ne PAS réduire le débit de transfert
- **Mémoire :** Ne pas charger le fichier entier en RAM
- **Compatible :** Garder la compatibilité Android/iOS/Desktop
- **Flutter 3.x :** Utiliser des APIs compatibles

## Tests à effectuer

1. **Test 1 :** Transférer un fichier de 10 Mo → Doit fonctionner
2. **Test 2 :** Transférer un fichier de 720 Mo → Doit recevoir 100%
3. **Test 3 :** Vérifier la RAM utilisée → Ne doit pas dépasser 500 Mo
4. **Test 4 :** Transférer plusieurs fichiers d'affilée → Doit fonctionner
5. **Test 5 :** Mobile → Desktop avec Photos/Vidéos → Doit fonctionner

## Questions à résoudre

1. Pourquoi le récepteur s'arrête-t-il à 2 Mo ?
2. Le DataChannel se ferme-t-il pendant le transfert ?
3. Les chunks sont-ils bien reçus dans l'ordre ?
4. Y a-t-il une erreur silencieuse dans `receiveChunk()` ?

## Livrable attendu

1. Code corrigé pour tous les fichiers
2. Explication des bugs trouvés
3. Tests de validation
4. Logs de débogage pour vérifier le bon fonctionnement