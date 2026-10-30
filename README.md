# GoSend

Application de partage de fichiers en réseau local, sans Internet, sans cloud et sans compte.
Écrite en Flutter, elle fonctionne sur Windows, Android, Linux et macOS.

Site officiel : https://gosend.pages.dev
Téléchargements : https://gosend.pages.dev/download

---

## Fonctionnalités

- Découverte automatique des appareils sur le réseau local (UDP par interface réseau + sondage de la table ARP pour les hotspots Android).
- Transfert direct de fichiers en HTTP entre les appareils, sans serveur intermédiaire.
- Envoi de messages texte entre appareils.
- Notifications et sons à la réception.
- Dossier de réception configurable.
- Interface sombre avec accents verts.

## Prérequis

- Flutter 3.38 ou plus récent (`flutter --version`).
- Pour Windows : Visual Studio Build Tools avec la charge de travail C++ Desktop.
- Pour Android : Android SDK installé et licences acceptées (`flutter doctor --android-licenses`).
- Pour l'installateur Windows : Inno Setup 6 (`ISCC.exe`).
- Pour publier : GitHub CLI authentifié (`gh auth status`).

---

## Lancer en développement

```powershell
flutter pub get
flutter run -d windows
flutter run -d <device-id>
```

---

## Publication des releases

> À faire à chaque modification publiée. Cette procédure produit les deux fichiers
> téléchargeables depuis le site (APK Android et installateur Windows).

### 1. Mettre à jour la version

Dans `pubspec.yaml`, incrémenter `version` (par exemple `2.0.0+1` devient `2.0.1+2`).
Mettre aussi à jour `AppVersion` dans `gosend.iss`.

### 2. Compiler l'APK Android

```powershell
cd C:\Users\User\OneDrive\Desktop\GoSend
flutter build apk --release
```

Résultat : `build\app\outputs\flutter-apk\app-release.apk`

### 3. Compiler la version Windows

```powershell
flutter build windows --release
```

Résultat : `build\windows\x64\runner\Release\gosend.exe`

### 4. Générer l'installateur Windows

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" gosend.iss
```

Résultat : `Output\GoSend_Setup.exe`

### 5. Renommer les fichiers pour la release

```powershell
$v = "2.0.0"
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "dist\GoSend-$v.apk" -Force
Copy-Item "Output\GoSend_Setup.exe" "dist\GoSend-Setup-$v.exe" -Force
```

Créer le dossier `dist` s'il n'existe pas : `New-Item -ItemType Directory -Force dist`.

### 6. Publier sur GitHub Releases

```powershell
git add -A
git commit -m "release: GoSend v$v"
git push

gh release create "v$v" `
  "dist\GoSend-$v.apk" `
  "dist\GoSend-Setup-$v.exe" `
  -R Deogratiasdev/gosend `
  --title "GoSend $v" `
  --notes "Nouveautés de la version $v."
```

Les liens de téléchargement stables du site pointent vers `releases/latest/download/`,
il suffit donc de créer la release pour que le site serve la nouvelle version.

### 7. Mettre à jour la page de téléchargement du site

Dans `C:\Users\User\OneDrive\Desktop\Bureau\gosend-site\download.html`, remplacer :

- `__APK_SIZE__` par la taille réelle de l'APK (par exemple `56.2 Mo`),
- `__EXE_SIZE__` par la taille réelle de l'installateur (par exemple `24.8 Mo`),
- `__RELEASE_DATE__` par la date de publication (par exemple `30 octobre 2026`),
- le numéro de version affiché et le nom des fichiers si la version change.

Puis redéployer :

```powershell
cd C:\Users\User\OneDrive\Desktop\Bureau\gosend-site
wrangler pages deploy . --project-name gosend
```

### Récapitulatif express

```powershell
flutter build apk --release
flutter build windows --release
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" gosend.iss
```

Puis : renommer, `gh release create`, mettre à jour `download.html`, redéployer.

---

## Structure du projet

```
lib/
  core/
    network/        découverte UDP et transfert HTTP
    notifications/  notifications locales
    audio/          sons de l'application
    theme/          gestion du thème
  models/           modèles de données
  ui/               écrans et thème
assets/             icône et sons
windows/ android/ linux/ macos/   plateformes
```

## Licence

Projet personnel de HOUNNOU Déo-Gratias. Tous droits réservés.
