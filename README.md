# MacCam-6

*Une citadelle cyberpunk poétique fait renaître une machine de 1987.*

MacCam-6 est une reconstruction fidèle, en Cocoa/Objective-C + C, de la **CAM-8** — la machine à automates cellulaires conçue par Tommaso Toffoli et Norman Margolus, documentée dans leur ouvrage *Cellular Automata Machines* (MIT Press, 1987). Ce n'est pas une resucée décorative : chaque mécanisme (voisinages, réversibilité, Margolus, sondes croisées entre demi-machines) a été transcrit puis **vérifié au calcul**, souvent au pixel et au bit près, avant d'être considéré comme acquis.

Le projet est la résurrection d'un MacCam original écrit en THINK C sur 68000 dans les années 90 par [cleobuline](https://github.com/cleobuline), dont les sources ont été perdues. Cette version renaît trente ans plus tard, avec la rigueur qu'un ordinateur des années 90 ne permettait pas de vérifier aussi facilement.

---

## Sommaire

- [Pourquoi ce projet](#pourquoi-ce-projet)
- [Aperçu des fonctionnalités](#aperçu-des-fonctionnalités)
- [Architecture](#architecture)
- [Structure du dépôt](#structure-du-dépôt)
- [Compilation](#compilation)
- [Prise en main](#prise-en-main)
- [Le langage CAM-Forth](#le-langage-cam-forth)
- [Les voisinages](#les-voisinages)
- [Le bestiaire de règles](#le-bestiaire-de-règles)
- [Le gaz FHP (chapitre 16)](#le-gaz-fhp-chapitre-16)
- [Réversibilité (chapitre 14)](#réversibilité-chapitre-14)
- [Export vidéo](#export-vidéo)
- [Limites connues](#limites-connues)
- [Feuille de route](#feuille-de-route)
- [Remerciements](#remerciements)

---

## Pourquoi ce projet

Toffoli et Margolus ont construit dans les années 80 une machine dédiée : un processeur dont chaque bit de mémoire ne connaît que ses voisins immédiats, mis à jour en parallèle, pas à pas, selon une règle programmable. C'est l'ancêtre direct de tout ce qu'on appelle aujourd'hui "cellular automata" — de Conway's Life aux automates de gaz sur réseau qui simulent des fluides.

MacCam-6 recrée cette machine sur Mac moderne, avec deux objectifs qui se sont avérés indissociables tout au long du développement : rester **fidèle au livre** (au point de transcrire littéralement des listings Forth de 1987), et rester **honnête sur ce qui fonctionne vraiment** — chaque affirmation de ce README a été testée avant d'être écrite.

## Aperçu des fonctionnalités

- **Interpréteur CAM-Forth complet**, fidèle au vocabulaire du tableau 7.2 du livre
- **Tous les voisinages majeurs** : Moore, VonNeumann, Margolus (avec PHASE, PHASE', HORZ/VERT), et un voisinage **pseudo-hexagonal** (chapitre 16) inédit dans le livre
- **CAM-A et CAM-B**, deux demi-machines couplées, toutes deux capables de Margolus (pas seulement CAM-A)
- **Sondes croisées** (`&CENTER`, `&CENTER'`) permettant à une demi-machine de lire l'état de l'autre — y compris en mode Margolus
- **Réversibilité automatique** (chapitre 14) : calcul de la table inverse après chaque compilation, bouton ⏪ pour remonter le temps
- **Run-cycles programmables** (§11.5) pour les séquences de phases personnalisées
- **Un vrai gaz FHP** (chapitre 16) à 6 canaux directionnels, avec particules au repos (FHP-II) pour une viscosité réglable, bords ouverts, vent continu
- **Vingt règles et plus** dans le bestiaire, du simple Jeu de la Vie à un générateur de bruit lattice-gas authentique piloté sur CAM-B
- **Export vidéo H.264**, avec échelle réglable, gel sur pause, inversion temporelle suivie en direct, et resynchronisation automatique avec toute modification de la grille pendant l'export
- **Palette flottante complète** : outils de dessin (dont un Spray isotrope pour perturbations sans biais), sélection de plan, réglages FHP, menu d'effacement par plan

## Architecture

Le cœur du moteur est en **C pur**, sans dépendance Apple — testé et compilé indépendamment de Cocoa tout au long du développement.

```
cam_forth.h / cam_forth.c   → l'interpréteur CAM-Forth : VM, compilateur, bâtisseurs de tables
cam_core.h  / cam_core.c    → le moteur de simulation : LUT Moore/VonNeumann, Margolus (CAM-A + CAM-B),
                               hexagonal, réversibilité, run-cycles
fhp.h       / fhp.c         → sous-système indépendant : le vrai gaz FHP à 6 directions (chapitre 16)
```

L'interface (Cocoa/Objective-C) reste une couche fine par-dessus ce cœur :

```
CAMView.h/.m                    → rendu NSView bitmap, pinceau, collage image (N/USER)
CAMPalettePanel.h/.m            → palette flottante (outils, plans, réglages FHP, menu Effacer)
Document.h/.m                   → NSDocument, boucle de simulation, export vidéo
CAMEditorWindowController.h/.m  → éditeur de règles secondaire
```

Cette séparation stricte entre cœur C et interface Cocoa n'est pas accidentelle : elle a permis de tester rigoureusement chaque mécanisme (compilation, exécution, réversibilité) dans un environnement Linux indépendant, sans jamais avoir besoin de compiler l'app complète pour vérifier la logique de fond.

## Structure du dépôt

```
cam-8/
├── cam-8.xcodeproj/
└── cam-8/
    ├── cam_core.h / cam_core.c
    ├── cam_forth.h / cam_forth.c
    ├── fhp.h / fhp.c
    ├── CAMView.h / CAMView.m
    ├── CAMPalettePanel.h / CAMPalettePanel.m
    ├── Document.h / Document.m
    ├── CAMEditorWindowController.h / CAMEditorWindowController.m
    ├── AppDelegate.h / AppDelegate.m
    └── regles/
        ├── critters.rule
        ├── hpp-gas.rule
        ├── tm-gas.rule
        ├── bbm.rule
        ├── dendrite.rule
        ├── dendrite-noise.rule
        ├── gaz-murs.rule
        ├── tube-worms.rule
        ├── ising.rule
        ├── hex-diffuse.rule
        ├── 2d-brownian.rule
        ├── 2d-brownian-trace.rule
        └── ... (voir le bestiaire ci-dessous)
```

## Compilation

Ouvrir `cam-8.xcodeproj` dans Xcode (testé sous Xcode 12.4, macOS Catalina, mais aucune dépendance récente particulière). Cmd+R pour lancer.

Pour distribuer l'app à des tiers, un DMG peut être généré simplement :

```bash
hdiutil create -volname "CAM-8" -srcfolder camdmg -ov -format UDZO CAM-8.dmg
```

L'app n'étant pas signée par un compte développeur Apple payant, macOS affichera un avertissement "développeur non identifié" à la première ouverture chez un tiers — clic droit → Ouvrir, ou Réglages Système → Confidentialité et sécurité → Ouvrir quand même.

## Prise en main

1. **Écrire ou charger une règle** dans l'éditeur de texte (voir le bestiaire pour des exemples prêts à l'emploi)
2. **⚙️ Compiler** pour construire la table
3. **Dessiner** un état initial (Pince, Cercle, Carré, Gomme, Spray) ou **Lancer** un semis aléatoire
4. **▶ Play** pour lancer la simulation ; **⏸ Stop** pour figer ; **⏪ Re...** pour inverser le temps si la règle est réversible
5. **🎬** pour exporter en vidéo

La palette flottante regroupe tous les réglages. Les contrôles spécifiques au gaz FHP (Vent, Bords ouverts, Viscosité, Spray isotrope) restent masqués tant que la case **Grille hexagonale** n'est pas cochée, pour ne pas noyer l'interface hors de ce contexte.

## Le langage CAM-Forth

Une règle typique :

```forth
N/MOORE
: LIFE 8SUM { 0 0 1 1 0 0 0 0 0 } CENTER AND
       8SUM { 0 0 0 1 0 0 0 0 0 } OR ;
MAKE-TABLE LIFE
```

### Vocabulaire de voisinage
`CENTER CENTER' NORTH SOUTH EAST WEST N.EAST N.WEST S.EAST S.WEST` (Moore) · `NORTH' SOUTH' EAST' WEST'` (VonNeumann) · `CW CCW OPP CW' CCW' OPP'` (Margolus) · `PHASE PHASE' HORZ VERT PHASES` (pseudo-voisins) · `RAND` (bruit, chapitre 8) · `&CENTER &CENTER' &CENTERS &PHASE &PHASE' &PHASES &HORZ &VERT &HV` (sondes croisées CAM-A ↔ CAM-B)

### Opérateurs
`+ - AND OR XOR NOT = <> > < 2* 2/ DUP DROP SWAP OVER IF ELSE THEN { }` (table de sélection) · `>PLN0 >PLN1 >PLN2 >PLN3 >PLNA >PLNB`

### Déclarations
`N/MOORE N/VONN N/MARG N/MARG-PH N/MARG-HV N/HEX` · `CAM-A CAM-B` · `&/CENTERS &/PHASES &/HV` · `CYCLE ... END-CYCLE` · `MAKE-TABLE` (et l'alias historique `MAKE-TABLE-MARGOLUS`)

Un mot défini par l'utilisateur (`: NOM ... ;`) peut **redéfinir un mot natif du langage** — vérifié explicitement : le dictionnaire utilisateur est consulté avant les mots intégrés, permettant par exemple de redéfinir `RAND` pour qu'il tire son bruit d'une autre source (voir `dendrite-noise.rule`).

## Les voisinages

| Déclaration | Description | Table |
|---|---|---|
| `N/MOORE` | 8 voisins + centre, classique | 8192 entrées |
| `N/VONN` | 4 voisins orthogonaux | 8192 entrées |
| `N/MARG` | Bloc Margolus 2×2, partition alternée | 32768 entrées* |
| `N/MARG-PH` | + PHASE (run-cycle) | idem |
| `N/MARG-HV` | + HORZ/VERT (parités spatiales) | idem |
| `N/HEX` | Pseudo-hexagonal, décalage en quinconce (chapitre 16, hors livre) | 256 entrées |

*Étendue le 6/7 de 2048 à 32768 entrées pour faire place au nibble de sonde croisée `&CENTER'`, nécessaire à une transcription fidèle du générateur de bruit du chapitre 16 (voir plus bas). Chaque demi-machine (CAM-A **et** CAM-B) peut désormais exécuter sa propre table Margolus, totalement indépendante — une extension du portage logiciel par rapport au matériel des années 80, où les deux modules étaient déjà symétriques par construction.

## Le bestiaire de règles

| Règle | Chapitre | Description |
|---|---|---|
| `critters.rule` | §12.8 | Inversion + rotation 180° si 2 particules — Margolus classique |
| `hpp-gas.rule` | §12.3–12.4 | Gaz diagonal avec collisions, **réversible**, conserve masse et quantité de mouvement |
| `tm-gas.rule` | §12.7 | Gaz H/V avec collisions, sensible à la phase |
| `bbm.rule` | §18.2 | Billiard Ball Model, verbatim du livre |
| `annealing.rule` | §5.4 | Majorité tordue de Vichniac |
| `decay.rule` | §8 | Extinction probabiliste (`RAND`) |
| `diffusion.rule` | §15 | Marche aléatoire par blocs |
| `dendrite.rule` | §15.7 | DLA — agrégation limitée par diffusion, givre sur germe peint |
| `dendrite-noise.rule` | §15.7 + §16 | **Transcription fidèle** de la p.167-168 : le même DLA, mais piloté par un vrai générateur de bruit lattice-gas (`STIR-SAMPLE-DELAY`) tournant sur CAM-B, lu via `&CENTER'` |
| `tube-worms.rule` | §9.3 | Vers tubicoles — règle-phare CAM-A/CAM-B, chrono 2 bits |
| `brians-brain.rule` | — | 3 états, traîne comète, CAM-A/CAM-B |
| `banks.rule` | §5.5 | Ordinateur universel |
| `hglass.rule` | §5.6 | Règle-énigme, table VONN-INDEX à 32 entrées |
| `gaz-murs.rule` | §15.2 + §12.4 | HPP-GAS avec parois indestructibles peintes au plan 1 ; **réversible**, y compris à travers les murs |
| `maree.rule` | §11.5 | Cycle palindrome à 8 temps, run-cycle personnalisé |
| `ising.rule` | §17 | Q2R microcanonique, énergie conservée exactement |
| `hex-diffuse.rule` | §16 | Banc d'essai du voisinage hexagonal — diffusion isotrope, croissance en hexagone prouvée |
| `2d-brownian.rule` | p.156 | Mouvement brownien 2D par rotation aléatoire de blocs Margolus |
| `2d-brownian-trace.rule` | p.156 | Idem, avec trace permanente accumulée sur le plan 1 (`CENTER CENTER' OR`) |
| `parity-flip.rule` | ch. 8/11 | Variante de TIME-TUNNEL, parité incluant CENTER lui-même |

`TIME-TUNNEL` (équation d'onde discrète, second ordre) est la règle chargée par défaut au démarrage.

## Le gaz FHP (chapitre 16)

Le vrai gaz de Frisch-Hasslacher-Pomeau vit dans son propre sous-système (`fhp.h/.c`), séparé du moteur CAM-Forth : une seule cellule booléenne ne peut représenter que de la densité, jamais une particule *en mouvement* avec une direction — d'où la nécessité de 6 canaux directionnels indépendants par cellule.

- **FHP-I** : collisions à 2 corps (paire frontale → axe transverse aléatoire) et à 3 corps (rotation déterministe des triplets symétriques, indispensable pour casser une quantité conservée parasite qui figeait le gaz en rubans)
- **FHP-II** : un 7e canal « au repos » (0, 1 ou 2 particules) — une paire frontale à quantité de mouvement nette nulle peut s'y absorber, et réciproquement en émettre une. La probabilité de conversion (**Viscosité**) est le bouton qui manquait à FHP-I pour régler la dissipation
- **Bords ouverts** : le gaz qui atteint le bord droit sort du domaine plutôt que de reboucler par le tore — indispensable pour une scène de soufflerie sans recirculation parasite
- **Vent d'Ouest continu** : réinjection permanente sur le bord gauche
- **Spray isotrope** : perturbation locale répartie sur les 6 directions sans biais, pour observer une onde qui s'amortit sans qu'un vent ne la pousse

**Limite connue** : la grille carrée de Margolus résiste structurellement à l'amortissement (voir plus bas) — c'est le vrai gaz FHP, sur sa grille hexagonale, qui amortit proprement les ondes, pas les règles Margolus classiques comme `HPP-GAS`.

## Réversibilité (chapitre 14)

Après chaque compilation, le moteur calcule automatiquement la table inverse et vérifie la bijectivité (`cam_can_reverse()`). Les conditions exactes :

- Aucune expédition vers le plan 1 (`>PLN1`) — les murs doivent rester éternels
- Indépendance vis-à-vis de `RAND` et des sondes croisées (`&CENTER'`) — une règle nourrie par du bruit externe n'est pas mécaniquement inversible sans connaître l'historique de la source
- **Bijection par tranche du plan 1** : contrairement à une première version trop stricte, une règle peut légitimement se comporter différemment selon la présence d'un mur (ex. `gaz-murs.rule`), tant que chaque comportement pris isolément reste une bijection

Démonstration la plus spectaculaire du bestiaire : un gaz `hpp-gas.rule` complètement thermalisé et méconnaissable après 100 pas retrouve **exactement**, bit pour bit, son état initial après 100 pas en arrière — la preuve cellulaire que le désordre apparent ne détruit jamais l'information.

## Export vidéo

- **Échelle réglable** (`auto`, ou une valeur explicite comme `0.5`, `2`, `3`) — échantillonnage au plus proche voisin, gère aussi bien l'agrandissement que la réduction
- **Gel sur Stop** : l'export continue d'écrire des frames identiques tant que la simulation est en pause — utile pour des effets de transition (figer sur une recomposition)
- **⏪ suivi en direct** : fonctionne aussi bien pour les règles Margolus réversibles que pour les règles du second ordre (échange de plans, ex. TIME-TUNNEL)
- **Resynchronisation automatique** : Compiler, Lancer, Effacer, et chaque coup de pinceau se répercutent dans l'export en cours, permettant d'enchaîner plusieurs simulations distinctes dans une seule vidéo continue
- **Mode FHP pris en charge** : un second chemin d'export clone le gaz plutôt que la grille CAM classique

## Limites connues

- **CAM-B ne sonde pas encore CAM-A en retour** — les sondes croisées ne fonctionnent que dans un sens (CAM-A lit CAM-B), câblées pour le seul besoin identifié à ce jour (`dendrite-noise.rule`)
- **L'amortissement d'ondes sur grille carrée (Margolus/HPP)** résiste structurellement : deux tentatives de règles dissipatives (`HPP-AMORTI`, `HPP-LOSSY`) n'ont pas produit d'amortissement net et reproductible — la géométrie hexagonale de FHP reste la voie qui fonctionne
- **Le tourbillon de von Kármán franc** n'a jamais été obtenu avec certitude sur FHP, malgré la viscosité réglable — un signal faible et bruité a été mesuré, pas un lâcher net et visible
- **La palette n'a pas de repli dynamique complet** : masquer les contrôles FHP laisse un espace vide au milieu de la fenêtre plutôt que de resserrer parfaitement toutes les sections

## Feuille de route

- Compteurs de population en temps réel (chapitre 17)
- Vote probabiliste et dérive génétique (chapitre 17, jamais construits)
- Croissances façon lichen, motifs géométriques (chapitre 5)
- Sondes croisées CAM-B → CAM-A (symétrie manquante)
- FHP : recherche d'un régime produisant un vrai lâcher tourbillonnaire
- `camgen` : générateur headless, pour Linux/VPS ou un portage Windows éventuel (le cœur C est déjà indépendant de Cocoa)

## Remerciements

À Tommaso Toffoli et Norman Margolus, dont le livre de 1987 reste, presque quarante ans plus tard, suffisamment précis pour qu'on puisse en transcrire les listings au mot près et les voir fonctionner. Et au MacCam original des années 90, dont cette version est la résurrection.

---

*Développé avec Claude (Anthropic) comme partenaire d'implémentation technique.*
