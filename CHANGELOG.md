# Changelog

Toutes les évolutions notables de **Titalium Repair Tool** sont documentées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le projet adhère au [versioning sémantique](https://semver.org/lang/fr/).

---

## [1.1.2] — 2026-05-09

### 🐛 Corrigé

- **Annulation d'opération bloquante** : `Run-Process` lisait stdout en mode synchrone caractère par caractère ; quand un processus enfant ne répondait plus (typiquement `net stop cryptsvc` quand le service Cryptographic Services est en train de stopper), le `Read()` bloquait indéfiniment et le check `$sync.CancelRequested` n'était jamais évalué — bouton « Annuler » sans effet. Lecture désormais **100 % asynchrone** via `DataReceivedEventHandler` + `BeginOutputReadLine`, et la boucle de polling vérifie cancel + exit toutes les 80 ms sans jamais bloquer.
- **Kill complet de l'arborescence de processus** : utilise désormais `taskkill /T /F /PID <pid>` au lieu de `Process.Kill()`. C'est indispensable pour les processus parents comme `net.exe` qui lancent des descendants (`sc.exe`, `services.exe` calls) — sinon le parent est tué mais les enfants continuent à bloquer le système.
- **Fermeture de la fenêtre quand une opération est hung** : `Window.Closing` force-kill maintenant l'arborescence de processus en cours via `taskkill /T /F`, et `Window.Closed` clôture la runspace dans un Task avec timeout 2s — plus de blocage à la fermeture, même si le processus enfant est zombie.

### ✨ Ajouté

- **Bouton « ✕ Arrêter »** directement dans le **bandeau de progression** (en haut, visible quand une tâche est en cours). Plus pratique et plus visible que le bouton « Annuler » du status bar (qui est toujours là en complément).
- **Tracking du processus courant** via `$sync.CurrentProcess` — permet un kill immédiat depuis l'UI sans passer par l'introspection de l'arborescence.

---

## [1.1.3] — 2026-05-09

### ✨ Ajouté

- **Logo Titalium personnalisé** en haut de l'app — l'image est injectée en base64 à la compilation par `Build-Exe.ps1` (le PNG source n'est pas versionné, fallback sur le « T » stylisé en exécution directe du `.ps1`)
- **Bouton « ✓ Tout »** sur tous les DataGrids avec checkboxes (Logiciels Winget, Logiciels installés, Bloatware, Pilotes, Démarrage, Services, Processus) — toggle smart : si tout coché → décoche tout, sinon coche tout
- **Mécanisme anti-orphelin de processus** : Job Object Windows avec `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`. Tous les processus enfants (sfc, dism, net, winmgmt…) sont automatiquement tués par Windows si le parent meurt. Plus aucun zombie possible.
- **Force-exit en `finally`** après `ShowDialog()` via `[Environment]::Exit(0)` — termine tous les threads (foreground + background). Plus de processus invisible (sans fenêtre) qui survit après un crash en init.

### 🐛 Corrigé

- **`Run-Process` ipconfig/ping bloquait** : `StreamReader.EndOfStream` lisait à l'avance et bloquait. Détection EOF désormais via `ReadLineAsync().Result == null`.
- **WMI verify crashait** : ajout de pré-checks PowerShell (`Get-Service Winmgmt` + requête CIM) + try/catch outer. Plus de crash sur sortie process trop rapide.
- **Catroot2 / SoftwareDistribution** : try/catch outer + redémarrage forcé des services dans le finally même en cas d'erreur (sinon Windows Update reste cassé).
- **SFC plantait** sous charge de sortie : refactor de `Run-Process` pour utiliser `StreamReader.ReadLineAsync` + `Task.WaitAny(100ms)` au lieu de `DataReceivedEventHandler` (les scriptblocks PS comme handlers .NET souffrent de runspace contention sous charge).
- **Pilotes — bouton d'aide MAJ** : ne ouvre plus un navigateur Google. Copie désormais les infos des pilotes sélectionnés dans le presse-papier et ouvre la page Windows native `ms-settings:windowsupdate-optionalupdates` (où Microsoft expose les drivers de son catalogue).
- **Inventaire pilotes lent** : `pnputil /enum-drivers` remplacé par `Get-CimInstance Win32_PnPSignedDriver` (~10× plus rapide), trié par date avec libellés visuels (`⚠ très ancien`, `⚠ ancien`).

### 🔧 Modifié

- **Tous les `Op-Info*`** (CPU, RAM, GPU, Disques, SMART, Uptime, Réseau) convertis en DataGrid Section/Propriété/Valeur — plus aucune sortie console pour les infos système.
- **`Build-Exe.ps1`** lit `logo.png` (gitignored) et l'injecte en base64 dans une copie temporaire du `.ps1` avant compilation. La copie temporaire est supprimée après compilation.

---

## [1.1.2] — 2026-05-09 (jamais releasé publiquement, fusionné dans 1.1.3)

### 🐛 Corrigé

- **Annulation d'opération bloquante** : `Run-Process` lisait stdout en mode synchrone caractère par caractère ; quand un processus enfant ne répondait plus (typiquement `net stop cryptsvc` quand le service Cryptographic Services est en train de stopper), le `Read()` bloquait indéfiniment et le check `$sync.CancelRequested` n'était jamais évalué — bouton « Annuler » sans effet. Lecture désormais **100 % asynchrone**, et la boucle de polling vérifie cancel + exit toutes les 80 ms sans jamais bloquer.
- **Kill complet de l'arborescence de processus** : utilise désormais `taskkill /T /F /PID <pid>` au lieu de `Process.Kill()`.
- **Fermeture de la fenêtre quand une opération est hung** : `Window.Closing` force-kill maintenant l'arborescence + `Window.Closed` clôture la runspace dans un Task avec timeout 2s.

### ✨ Ajouté

- **Bouton « ✕ Arrêter »** directement dans le **bandeau de progression** (en haut, visible quand une tâche est en cours).
- **Tracking** du processus courant via `$sync.CurrentProcess` — kill immédiat depuis l'UI.

---

## [1.1.1] — 2026-05-09

### 🐛 Corrigé

- **Crash au démarrage du `.exe`** : `« Cannot bind argument to parameter 'Path' because it is null »`. En mode ps2exe, ni `$PSScriptRoot` ni `$MyInvocation.MyCommand.Path` ne sont peuplés. Fallback désormais robuste sur `[System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName`.
- **Recherche de pilotes** : `HRESULT 0x80244011` (`WU_E_PT_REGISTRATION_NOT_SUPPORTED`) sur les postes hors domaine ou avec WSUS mal configuré. On enregistre désormais explicitement le service Microsoft Update (GUID `7971f918-a847-4430-9279-4a52d1efe18d`) et on cherche via `ServerSelection=3 + ServiceID`.
- **Fallback inventaire pilotes** : si Microsoft Update reste inaccessible, l'app bascule automatiquement sur l'inventaire `pnputil /enum-drivers`, **trié par date** (les plus anciens en haut, candidats probables à une mise à jour). L'utilisateur voit ses pilotes obsolètes et peut les mettre à jour manuellement via Settings ou le site du fabricant.
- **Auto-élévation** : détecte désormais le mode `.ps1` vs `.exe` et relance la bonne cible avec UAC (le mode `.ps1` relance `powershell.exe -File`, le mode `.exe` se relance lui-même via le path du processus courant).

---

## [1.1.0] — 2026-05-09

> ⚠️ Cette release contient un bug critique au démarrage du `.exe`. **Utilisez la v1.1.1 ou supérieure.**


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

[1.1.2]: https://github.com/titalium/TitaliumRepair/releases/tag/v1.1.2
[1.1.3]: https://github.com/titalium/TitaliumRepair/releases/tag/v1.1.3
[1.1.2]: https://github.com/titalium/TitaliumRepair/releases/tag/v1.1.2
[1.1.1]: https://github.com/titalium/TitaliumRepair/releases/tag/v1.1.1
[1.1.0]: https://github.com/titalium/TitaliumRepair/releases/tag/v1.1.0
[1.0.0]: https://github.com/titalium/TitaliumRepair/releases/tag/v1.0.0
