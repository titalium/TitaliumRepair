# Changelog

Toutes les évolutions notables de **Titalium Repair Tool** sont documentées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le projet adhère au [versioning sémantique](https://semver.org/lang/fr/).

---

## [1.1.0] — 2026-05-09

### ✨ Ajouté

- **Tableau de bord (page d'accueil)** : 6 cartes de santé — disque libre, antivirus, MAJ Windows, RAM, BSOD 30j, uptime / dernier point de restauration
- **Détection antivirus tiers** via `root\SecurityCenter2` (Avast, Bitdefender, Kaspersky, ESET…) — affiche le produit actif si Defender est désactivé
- **Bandeau de progression global** avec pourcentage en temps réel — parsing automatique des sorties SFC, DISM et autres processus
- **Lien Titalium cliquable** dans le footer → ouvre [titalium.fr](https://titalium.fr)
- **Vérification de mise à jour** via API GitHub Releases (bouton « Vérifier MAJ » dans le header)
- **Logiciels installés (winget)** : DataGrid avec filtre rapide + désinstallation sélective via cases à cocher
- **Pilotes** : recherche des mises à jour via Windows Update API + DataGrid + installation sélective
- **Performances — Démarrage** : DataGrid des programmes au démarrage avec désactivation sélective (suppression du registre)
- **Performances — Services** : DataGrid avec actions de groupe (start / stop sur sélection)
- **Performances — Processus** : DataGrid des top 30 processus par RAM avec kill sélectif
- **Désinstaller bloatware Windows** : DataGrid des Appx préinstallées (Candy Crush, Xbox, Cortana, Solitaire, etc.) avec désinstallation par lot
- **Mots de passe WiFi sauvegardés** : extraction via `netsh wlan show profile` + export CSV
- **Caches navigateurs** : nettoyage Edge / Chrome / Firefox / Brave (ferme le processus avant)
- **Toggle hibernation** : active / désactive `hiberfil.sys` pour libérer ~RAM Go d'espace disque
- **File d'impression** : vide la file bloquée (stop spooler + clean PRINTERS + restart)
- **Toggle télémétrie Windows** : active / désactive DiagTrack, dmwappushservice, WerSvc + tâches planifiées (backup auto avant)
- **Liste des derniers BSOD** : événements 1001 / 41 / 6008 du System Log + dossier minidumps
- **Mode performances visuelles** : désactive animations Aero, transparence, ombres
- **Profils de maintenance** : 3 profils prédéfinis (Nettoyage hebdo / Réparation système / Avant vente PC) + profils JSON personnalisables
- **God Mode shortcut** : créé en un clic sur le bureau
- **Shells admin** : raccourcis PowerShell / Cmd élevés
- `version.json` : manifest de version pour les release GitHub
- `CHANGELOG.md` : historique des versions

### 🐛 Corrigé

- **Cross-thread `Add_Rendering`** : les particules ne s'animaient pas car `CompositionTarget.Rendering` est un événement statique. Remplacé par un `DispatcherTimer` à 16ms.
- **Cross-thread WPF + PowerShell** : les opérations Op-* (Write-Log, mise à jour de DataGrid depuis le runspace worker) faisaient planter l'app avec « *The calling thread cannot access this object* ». Refactor complet du marshalling : pattern producteur-consommateur via `ConcurrentQueue` + `DispatcherTimer` UI thread.
- **Encodage UTF-8 sans BOM** : PowerShell 5.1 lisait le script en ANSI, cassant les caractères accentués et `—`. Tous les fichiers `.ps1` sont désormais en UTF-8 + BOM.
- **Apostrophes mal échappées** : 3 chaînes single-quotées contenaient `\'` (qui ne fonctionne pas en PowerShell — il faut `''` ou des guillemets doubles). Corrigé.
- **Fermeture silencieuse de l'app** : ajout d'un gestionnaire global `Dispatcher.UnhandledException` qui affiche désormais les erreurs dans une MessageBox au lieu de fermer l'app.

### 🔧 Modifié

- Sidebar passe de 12 à 14 catégories (ajout de **Tableau de bord** en première position et **Avancé** en fin de liste)
- Les opérations qui sortaient en console (logiciels installés, pilotes, démarrage, services, processus) sont désormais affichées dans des **DataGrids interactifs** avec sélection multiple et actions de groupe
- `Run-Process` capture désormais les sorties caractère par caractère pour détecter les pourcentages affichés sur la même ligne (style SFC qui rafraîchit `XX% complete...`)

---

## [1.0.0] — 2026-05-09

### ✨ Premier release publique

- Refonte complète de `repair.bat` (135 lignes) en application WPF moderne
- Interface sombre futuriste avec animation de particules + lignes de connexion
- 12 catégories couvrant : Réparation système, Windows Update, Nettoyage, Registre, Réseau, Logiciels (winget), Pilotes, Performances, Sécurité, Récupération, Infos système, Outils rapides
- Worker runspace asynchrone (UI réactive même pendant un SFC de 10+ minutes)
- Console de logs live + persistance dans `Documents\TitaliumRepair\Logs\`
- Backups automatiques du registre / hosts avant toute modification
- Bouton « Annuler » fonctionnel
- Auto-élévation UAC + manifest `requireAdministrator` dans le `.exe`
- Build script (`Build-Exe.ps1`) qui produit un `.exe` portable autonome via ps2exe

---

[1.1.0]: https://github.com/titalium/TitaliumRepair/releases/tag/v1.1.0
[1.0.0]: https://github.com/titalium/TitaliumRepair/releases/tag/v1.0.0
