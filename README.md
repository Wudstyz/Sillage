<div align="center">

<img src="docs/icon-256.png" width="128" alt="Icône de Sillage">

# Sillage

**Votre agenda, et la trace de ce que vous avez vraiment fait de votre journée.**

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-lightgrey) ![Licence MIT](https://img.shields.io/badge/licence-MIT-green)

[English version](README.en.md)

<img src="docs/screenshots/01-journee.png" width="760" alt="Sillage : la frise d'une journée, prévu à gauche, réel à droite">

</div>

Sillage est une app Mac gratuite et libre qui réunit un **calendrier** et un **journal de bord de la journée**.

- **Planifiez** vos rendez-vous : le médecin, une réunion… Quoi qu'il arrive, de telle heure à telle heure, vous y êtes.
- **Démarrez une tâche** à l'instant où vous la commencez (« je commence l'appli à 16 h 34 »). Pas besoin de savoir quand elle finira : elle reste *en cours* et grandit sur la frise jusqu'à ce que vous la terminiez.
- **Faites plusieurs choses à la fois** : les tâches simultanées se placent côte à côte.
- **Le soir, relisez votre journée** : de telle heure à telle heure la douche, le repas, le site, le rendez-vous, le coucher. Le prévu (pointillés) et le réel (plein) sont face à face, avec un **bilan par catégorie**.

Tout reste **sur votre Mac** : aucun compte, aucun réseau, aucune donnée envoyée.

## Utilisation

| Je veux… | Je fais… |
|---|---|
| Commencer une tâche maintenant | Panneau de gauche : titre, catégorie, **Démarrer maintenant** |
| Répéter un rendez-vous (kiné chaque mercredi, loyer chaque mois…) | Dans la fiche : **Répéter** (jour, semaine avec choix des jours, mois, année), « toutes les N », « jusqu'au ». Chaque occurrence reste modifiable, déplaçable et honorable séparément ; les séries sont prolongées automatiquement un an à l'avance |
| Supprimer une série | Fiche d'une occurrence → **Supprimer** → « Cette occurrence seulement » ou « Celle-ci et les suivantes » (ce qui a déjà été vécu reste) |
| Être prévenu avant un rendez-vous | Dans la fiche : **Rappel** (à l'heure, 5 min, 15 min, 1 h, 1 jour avant) : notification macOS, même fenêtre fermée |
| Lancer une activité courante (douche, repas, sommeil, trajet, pause, sport) | Un clic sur un **raccourci** |
| Enchaîner deux tâches | Case « Terminer la tâche en cours » (cochée par défaut) |
| Terminer une tâche en cours | Bouton ■ dans « En cours » |
| Signaler que je suis arrivé à un rendez-vous | Clic droit sur le rendez-vous → **J'y suis** : la tâche réelle démarre, et la frise affiche le retard ou l'avance |
| Ajouter un rendez-vous | **+ → Rendez-vous prévu** (⌘N) |
| Noter une activité déjà passée (douche, repas…) | **+ → Activité passée** (⇧⌘N) |
| Créer une plage directement | **Glisser** dans le vide de la frise (colonne Prévu ou Réel), alignée au quart d'heure |
| Déplacer une activité | **Glisser** le bloc |
| Changer sa durée | **Étirer** le bord bas du bloc |
| Corriger une heure oubliée | Clic sur le bloc dans la frise |
| Agir sans ouvrir la fenêtre | **Barre de menus** : la tâche en cours et son chronomètre y sont affichés ; le panneau montre le prochain rendez-vous (avec **J'y suis**), permet d'arrêter une tâche, d'en démarrer une ou d'utiliser un raccourci. Fermer la fenêtre laisse Sillage actif ; **Quitter** l'arrête |
| Changer de vue | **Jour / Semaine / Mois** (sélecteur en haut à droite, ⌘1 ⌘2 ⌘3). La **semaine** montre sept jours côte à côte, prévu en pointillés et réel en plein ; le **mois** montre une case par jour avec les rendez-vous et une **barre de couleurs** du temps réellement passé. Un clic sur un jour l'ouvre. Le bilan de la barre latérale suit la période affichée |
| Naviguer | ‹ › ou ⌘← ⌘→ (un jour, une semaine ou un mois selon la vue) ; aujourd'hui : ⌘T |

Les données sont dans `~/Library/Application Support/Sillage/data.json` (JSON lisible, écriture atomique). Une copie par jour est gardée dans `Sauvegardes/` (14 jours). Si le fichier devenait illisible, il est mis de côté (`data.corrompu-…`) et jamais écrasé. Une tâche restée « en cours » plus de 12 h est signalée comme oubliée.

## Installation

1. Téléchargez `Sillage.dmg` depuis les [Releases](../../releases) et glissez **Sillage** dans *Applications*.
2. L'app n'est pas signée par Apple : à la première ouverture, faites un clic droit sur l'app → **Ouvrir** → **Ouvrir**.

## Construire soi-même

Prérequis : Xcode ou ses outils en ligne de commande (macOS 13+, Apple Silicon).

```bash
./build_app.sh   # compile, génère l'icône, assemble dist/Sillage.app
./make_dmg.sh    # crée dist/Sillage.dmg
swift test       # tests du cœur
```

Le cœur (`SillageCore`) est séparé de l'interface SwiftUI (`SillageApp`) ; aucune bibliothèque tierce.

## Idées pour la suite

- Export / import (JSON, iCal) et lecture de vos calendriers existants
- Catégories et raccourcis personnalisés
- Raccourci clavier global pour démarrer / terminer une tâche
- Récapitulatif de fin de journée

## Licence

[MIT](LICENSE) : libre d'utilisation, de modification et de redistribution. © Damien POLLET (Wudstyz)
