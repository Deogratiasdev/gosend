Clear-Host

# Chemin de scrcpy
$ScrcpyPath = "C:\Users\User\OneDrive\Desktop\scrcpy-win64-v3.3.4"

# Vérifier le dossier
if (!(Test-Path $ScrcpyPath)) {
    Write-Host "Le dossier scrcpy est introuvable !" -ForegroundColor Red
    Pause
    exit
}

Set-Location $ScrcpyPath

# Demande de l'adresse IP
$Adresse = Read-Host "Entrez l'adresse IP du téléphone (ex: 10.112.253.210:5555)"

Write-Host ""
Write-Host "Activation du mode TCP/IP..."
.\adb.exe tcpip 5555

Write-Host ""
Write-Host "Connexion au téléphone..."
.\adb.exe connect $Adresse

Write-Host ""
Write-Host "=============================="
Write-Host " Demarrage du controle ecran"
Write-Host "=============================="
Write-Host "1. Oui (écran du téléphone éteint)"
Write-Host "2. Oui (écran allumé)"
Write-Host "3. Quitter"
Write-Host ""

$Choix = Read-Host "Votre choix"

switch ($Choix)
{
    "1" {
        Write-Host "Lancement de scrcpy..."
        .\scrcpy.exe -s $Adresse --turn-screen-off
    }

    "2" {
        Write-Host "Lancement de scrcpy..."
        .\scrcpy.exe -s $Adresse
    }

    "3" {
        Write-Host "Au revoir."
        exit
    }

    default {
        Write-Host "Choix invalide."
    }
}

Pause