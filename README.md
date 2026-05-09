<div align="center">

# ⚡ Titalium Repair Tool

**Couteau-suisse de réparation et d'optimisation Windows, taillé pour les techniciens et les power-users.**

[![Version](https://img.shields.io/badge/version-1.1.3-00D9FF?style=flat-square)](https://github.com/titalium/TitaliumRepair/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-lightgrey?style=flat-square)](#)
[![Made by](https://img.shields.io/badge/made%20by-Titalium-00D9FF?style=flat-square)](https://titalium.fr)

</div>

---

## 🧭 À propos

**Titalium Repair Tool** est une suite tout-en-un, gratuite et open source, qui regroupe en un seul exécutable portable les opérations de maintenance Windows que tu enchaînes habituellement dans une dizaine de fenêtres différentes — `sfc`, `DISM`, `chkdsk`, `winget`, `pnputil`, `netsh`, `regedit`, l'observateur d'événements, le gestionnaire de tâches…

L'outil est pensé pour deux profils :

- **Le technicien support** qui doit diagnostiquer rapidement un poste, lister les MAJ Windows et logiciels en attente, voir l'état de l'antivirus, virer le bloatware préinstallé, vider les caches, ou appliquer un profil de maintenance complet en un clic.
- **L'utilisateur curieux** qui veut comprendre ce qui ralentit son PC : top processus en RAM, services actifs, programmes au démarrage, derniers BSOD, pilotes obsolètes — tout exposé en DataGrids interactifs avec actions de groupe.

L'interface est moderne (thème sombre, animation de particules, bandeau de progression live) et tout passe par des **confirmations + backups automatiques** avant la moindre opération destructive : pas de surprise.

Pas d'installation, pas de runtime à déployer — un seul `.exe` portable que tu copies sur n'importe quel poste Windows 10 / 11.

---

## ✨ Points forts

- **13 catégories**, ~80 fonctionnalités — toutes accessibles depuis une sidebar claire
- **Tableau de bord santé** (1ʳᵉ page) : disque, antivirus tiers détectés via SecurityCenter2, MAJ Windows, RAM, BSOD 30j, uptime, dernier point de restauration
- **Bandeau de progression global** avec pourcentage en temps réel — parse les sorties de SFC, DISM, etc.
- **DataGrids interactifs** avec sélections multiples : MAJ winget, logiciels installés, pilotes Windows Update, programmes de démarrage, services, processus, bloatware Appx
- **Mots de passe WiFi** sauvegardés affichés en clair (avec export CSV)
- **Profils de maintenance** : combos d'opérations en JSON sauvegardables (« Nettoyage hebdo », « Réparation système », « Avant vente PC »)
- **Vérification de mise à jour** intégrée via l'API GitHub Releases
- **Backups automatiques** du registre, du fichier hosts, des services télémétrie avant toute modification
- **100 % portable** : un `.exe` autonome, UAC géré par le manifest, aucune dépendance

---

## 🚀 Démarrage rapide

### Utilisation directe (utilisateur final)

1. Télécharge `TitaliumRepair.exe` depuis la [dernière release](https://github.com/titalium/TitaliumRepair/releases/latest)
2. Double-clique → l'UAC s'ouvre → la fenêtre apparaît
3. C'est tout — aucune installation, aucune dépendance

### Mode développement (depuis le source)

```powershell
# Lance directement le script PowerShell avec auto-élévation
.\TitaliumRepair.cmd
```

### Build d'un nouveau `.exe` portable

```powershell
.\Build-Exe.ps1 -Version 1.1.0.0
```

Ce script installe automatiquement le module `ps2exe` (PSGallery) si absent, puis compile `TitaliumRepair.ps1` en `TitaliumRepair.exe` avec :
- `-noConsole` : pas de fenêtre console résiduelle
- `-STA` : apartment requis par WPF
- `-requireAdmin` : UAC intégré au manifest
- Métadonnées : auteur Titalium, version, copyright

---

## 📁 Structure du repo

| Fichier | Rôle |
|---|---|
| `TitaliumRepair.ps1` | Script principal — XAML embarqué + toute la logique |
| `TitaliumRepair.cmd` | Launcher dev avec auto-élévation |
| `Build-Exe.ps1` | Compilation en `.exe` portable via ps2exe |
| `version.json` | Manifest de version (publié comme asset de release) |
| `CHANGELOG.md` | Historique détaillé des versions |
| `LICENSE` | Apache License 2.0 |
| `repair.bat` | Ancien script (conservé en fallback historique) |

---

## 🗂️ Fonctionnalités par catégorie

<details>
<summary><b>📊 Tableau de bord</b> — Vue d'ensemble santé du système</summary>

- Espace disque libre (avec barre colorée selon seuil)
- Antivirus actif (Windows Defender ou tiers via SecurityCenter2)
- Mises à jour Windows en attente (compteur)
- RAM utilisée
- BSOD des 30 derniers jours
- Uptime + dernier point de restauration
</details>

<details>
<summary><b>🛠️ Réparation système</b></summary>

- SFC `/scannow` (avec progression %)
- DISM CheckHealth / ScanHealth / RestoreHealth / AnalyzeComponentStore
- Réparation complète (enchaîne DISM + SFC)
- Réenregistrement des DLL système
- Vérification + réparation du WMI
- Planification CHKDSK au reboot
- Réparation BCD (`bootrec`)
</details>

<details>
<summary><b>🔄 Windows Update</b></summary>

- Reset complet (services + caches SoftwareDistribution / catroot2)
- Recherche manuelle, historique
- Lister les MAJ en attente sans installer
</details>

<details>
<summary><b>🧹 Nettoyage</b></summary>

- %TEMP%, Windows\Temp, Prefetch, miniatures, corbeille
- SoftwareDistribution, catroot2, Delivery Optimization
- Caches navigateurs : Edge, Chrome, Firefox, Brave
- Disk Cleanup (cleanmgr) + sageset
- Suppression Windows.old
- Nettoyage complet en un clic
</details>

<details>
<summary><b>📋 Registre (avec backup auto)</b></summary>

- Sauvegarde complète (HKLM, HKCU, HKCR exportés en `.reg`)
- Désinstallations invalides, démarrage mort, MUICache, RecentDocs
</details>

<details>
<summary><b>🌐 Réseau</b></summary>

- ipconfig, ping, traceroute, flush DNS
- Release / Renew IP
- Reset Winsock, TCP/IP, proxy WinHTTP
- Réinitialiser hosts (avec backup)
- Reset complet pile réseau
- Mots de passe WiFi sauvegardés + export CSV
</details>

<details>
<summary><b>📦 Logiciels (winget)</b></summary>

- DataGrid des MAJ disponibles avec checkboxes — pas de mise à jour automatique
- DataGrid des logiciels installés avec filtre + désinstallation sélective
- Recherche, install, uninstall, export, import
</details>

<details>
<summary><b>🔌 Pilotes</b></summary>

- Recherche des MAJ via Windows Update API + DataGrid + installation sélective
- Lister tous les pilotes (pnputil)
- Sauvegarder les pilotes
- Périphériques avec problèmes Device Manager
</details>

<details>
<summary><b>⚡ Performances</b></summary>

- Programmes au démarrage : DataGrid + désactivation sélective
- Services Windows : DataGrid + start/stop sélectif
- Top processus : DataGrid + kill sélectif
- Plan d'alimentation, mode performances visuelles, toggle hibernation
- Désinstaller bloatware Windows : DataGrid des Appx préinstallés
</details>

<details>
<summary><b>🛡️ Sécurité</b></summary>

- Defender (statut, MAJ signatures, scan rapide / complet)
- MRT, statut activation Windows
- Calcul hash MD5 / SHA1 / SHA256 d'un fichier
- Toggle télémétrie Windows (DiagTrack, dmwappushservice, WerSvc) avec backup auto
</details>

<details>
<summary><b>💾 Récupération</b></summary>

- Points de restauration : créer / lister
- Réparer le BCD
- Liste des derniers BSOD via Event Log + dossier minidumps
</details>

<details>
<summary><b>ℹ️ Infos système</b></summary>

- Récap (OS, CPU, RAM, build), détail CPU/RAM/GPU/disques
- Santé disques (SMART), rapport batterie (laptop)
- Uptime, IP / MAC
</details>

<details>
<summary><b>⚙️ Outils rapides</b></summary>

Lance directement : regedit, services.msc, devmgmt.msc, eventvwr, taskmgr, diskmgmt.msc, msconfig, msinfo32, perfmon, resmon, control, settings, vider file d'impression bloquée.
</details>

<details>
<summary><b>🚀 Avancé</b></summary>

- Profils de maintenance : 3 prédéfinis (hebdo / réparation / avant-vente) + profils JSON personnalisables
- Création God Mode shortcut sur le bureau
- Shells PowerShell / Cmd admin
</details>

---

## 💾 Emplacement des données

Tous les artefacts sont stockés dans le dossier utilisateur (jamais dans le dossier d'install — l'app reste portable) :

```
%USERPROFILE%\Documents\TitaliumRepair\
├── Backups\    # Exports .reg, hosts.bak, état télémétrie...
├── Logs\       # Journaux horodatés par session
└── Profiles\   # Profils de maintenance JSON
```

---

## 🔄 Vérification de mise à jour

L'app intègre un bouton **Vérifier MAJ** dans le header qui interroge l'API GitHub Releases (`https://api.github.com/repos/titalium/TitaliumRepair/releases/latest`).

Le bouton compare le `tag_name` de la release la plus récente avec `$script:AppVersion` du script. Si une version plus récente est publiée → MessageBox proposant d'ouvrir la page de release.

---

## 🛠️ Publier une nouvelle version

1. **Bump la version** dans `TitaliumRepair.ps1` :
   ```powershell
   $script:AppVersion = '1.2.0'
   ```
2. **Mets à jour** `CHANGELOG.md` et `version.json` avec la liste des changements
3. **Compile** : `.\Build-Exe.ps1 -Version 1.2.0.0`
4. **Tague** : `git tag v1.2.0 && git push --tags`
5. **Crée la release** sur GitHub avec le tag + upload `TitaliumRepair.exe` (et optionnellement `version.json`) comme assets
6. **Vérifie** : le bouton « Vérifier MAJ » d'une instance v1.1.0 doit détecter la v1.2.0

---

## 📜 Licence

Distribué sous licence **Apache License 2.0** — voir [`LICENSE`](LICENSE).

Tu peux librement utiliser, modifier et redistribuer ce code, à condition de conserver l'attribution.

---

## 🏗️ Architecture technique

- **PowerShell 5.1+** (compatible PS 7) pour la logique
- **WPF** via XAML embarqué (single-quoted here-string) pour l'interface
- **DispatcherTimer 16ms** pour l'animation des particules + connexions
- **Runspace + synchronized hashtable + ConcurrentQueue** : pattern producteur-consommateur pour le marshalling UI cross-thread (évite les pièges classiques PS+WPF)
- **ps2exe** (fork MScholtes) pour le packaging `.exe`
- **Aucune dépendance runtime** : PowerShell + .NET Framework sont natifs Windows 10/11

---

## 🤝 Contribuer

Les PR sont bienvenues. Pour signaler un bug ou proposer une fonctionnalité, [ouvre une issue](https://github.com/titalium/TitaliumRepair/issues).

---

<div align="center">

Made with ♥ by **[Titalium](https://titalium.fr)**

</div>
