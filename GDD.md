# Balthazar — GDD

## 1. Intention

Les jeux de Belote sur Android sont décevants. Balthazar sert à jouer aux cartes entre amis, en ligne, sur téléphone en paysage :
- d'abord la Belote classique avec annonces ;
- puis la Coinche, le Tarot et d'autres jeux dans la même app.

Les règles se règlent : chaque table choisit ses variantes.

## 2. Plateforme et réseau

- Godot 4.7, GDScript, export Android (arm64) construit par la CI. Écran en **paysage**.
- **Jeu en ligne** : Tube (WebRTC pair-à-pair, trackers WebTorrent publics). L'hôte crée une table et partage un code ; les amis le saisissent. Pas de serveur ni de compte.
- L'hôte fait autorité : il tient le paquet et n'envoie à chaque joueur que sa main et ce qui est visible sur la table.
- Les places vides sont tenues par des bots.
- **Plus tard** :
  - un annuaire de tables publiques sur Firebase Realtime Database (offre gratuite, lu en REST à la demande, une fiche par table qui expire) ;
  - le jeu hors ligne autour d'une même table (Nearby Connections, plugin Android à écrire).
- Google Play Games n'offre plus de multijoueur depuis 2020.

## 3. Belote classique (règles de référence)

À faire valider par l'auteur avant le moteur. Chaque point marqué *(variante)* devient une option du RuleSet.

### 3.1 Joueurs, cartes, sens
- 4 joueurs en 2 équipes, partenaires face à face. Jeu de 32 cartes.
- Le jeu tourne dans le **sens des aiguilles d'une montre**. Le joueur à gauche du donneur parle et joue en premier.

### 3.2 Donne et prise
- Le donneur distribue 3 puis 2 cartes à chacun (5 cartes) et retourne la carte suivante (la « retourne »).
- **Premier tour** : chacun, à partir du joueur à gauche du donneur, prend à la couleur de la retourne ou passe.
- **Second tour** : si tout le monde a passé, chacun peut choisir une autre couleur d'atout ou passer.
- Si personne ne prend, on redistribue. La donne passe au joueur suivant, à gauche.
- Le preneur reçoit la retourne et 2 cartes ; les autres reçoivent 3 cartes. Chacun a alors 8 cartes.

### 3.3 Valeur des cartes
| | V | 9 | A | 10 | R | D | 8 | 7 |
|---|---|---|---|---|---|---|---|---|
| **Atout** | 20 | 14 | 11 | 10 | 4 | 3 | 0 | 0 |

| | A | 10 | R | D | V | 9 | 8 | 7 |
|---|---|---|---|---|---|---|---|---|
| **Hors atout** | 11 | 10 | 4 | 3 | 2 | 0 | 0 | 0 |

Total : 152 points, plus 10 de der, soit 162.

### 3.4 Jeu de la carte
- **Fournir** : il faut jouer la couleur demandée si on en a.
  - À l'atout, il faut **monter** (jouer plus fort que le meilleur atout du pli) si on le peut.
- **Couper** : si on n'a pas la couleur demandée, il faut couper.
  - Exception : on joue ce qu'on veut si le partenaire est maître du pli. *(variante : obligation de couper même si le partenaire est maître)*
- **Surcouper** : si le pli est déjà coupé, il faut surcouper si on le peut.
  - Si on ne peut pas surcouper et que le partenaire n'est pas maître, il faut **sous-couper** (« pisser ») si on a de l'atout. On ne se défausse que si on n'a plus d'atout. *(variante : sous-coupe libre)*
- Le gagnant du pli entame le suivant.

### 3.5 Belote-rebelote
- Roi et Dame d'atout dans la même main : 20 points, annoncés en jouant la première (« belote ») puis la seconde (« rebelote »).
- Ces 20 points restent à l'équipe qui les détient, même si le contrat chute.

### 3.6 Annonces
- Les annonces se déclarent pendant le premier pli et se montrent au second.
- **Suites**, dans l'ordre naturel A R D V 10 9 8 7, quelle que soit la couleur :

  | Annonce | Cartes | Points |
  |---|---|---|
  | Tierce | 3 | 20 |
  | Cinquante | 4 | 50 |
  | Cent | 5 et plus | 100 |

- **Carrés** :

  | Carré de | Points |
  |---|---|
  | Valets | 200 |
  | 9 | 150 |
  | As, 10, Rois, Dames | 100 |
  | 8 ou 7 | 0 (ne valent rien) |

- Seule l'équipe qui détient la meilleure annonce marque, et elle marque alors toutes ses annonces.
  - On compare d'abord les points, puis la hauteur de la carte la plus haute.
  - À égalité, une suite à l'atout l'emporte.
  - Deux suites égales hors atout : le premier joueur à parler l'emporte. *(à confirmer)*
- *(variante : annonces désactivées)*

### 3.7 Décompte d'une donne
- Le preneur doit faire **plus de points** que la défense, en comptant cartes, annonces et belote.
  - S'il réussit, chaque équipe marque ses points.
  - S'il échoue (**dedans**), la défense marque 162 plus toutes les annonces ; la belote reste à ceux qui l'ont.
- **Capot** : une équipe fait les 8 plis et marque 250 au lieu de 162.
- **Litige** (égalité, par exemple 81 à 81) : la défense marque ses points. Ceux du preneur sont mis en réserve et vont à l'équipe qui gagne la donne suivante.
- **Arrondi** : les points de chaque équipe sur la donne sont arrondis à la dizaine puis divisés par 10.
  - Un 5 arrondit en dessous et un 6 au-dessus : 15 → 1, 16 → 2, 17 → 2.
  - Une donne vaut donc 16 points, ou 17 quand les deux équipes finissent en 6 (96 et 66 donnent 10 + 7).
  - Le capot vaut 25, un dedans 16 plus les annonces, une tierce 2 et la belote 2.
  - La réussite du contrat se juge sur les points bruts, avant arrondi.
  - *(variante : points bruts sans arrondi)*
- La partie se joue en **101 points** *(variante : 501 ou 1000 en points bruts)*.

## 4. Autres jeux (plus tard)
- **Coinche** : enchères 80 à 160, puis capot ; coinche et surcoinche. Elle réutilise le jeu de la carte de la Belote ; seuls l'enchère et le décompte changent.
- **Tarot** : 78 cartes, 3 à 5 joueurs, avec son propre moteur.
- Manille, Président… selon l'envie.

## 5. Bots
- Des bots à règles simples choisissent parmi les coups légaux.
- Ils tiennent les places vides et jouent des milliers de parties sans tête dans les tests.

## 6. Parties classées (un jour)
- Entre amis, faire confiance à l'hôte suffit. Pour du classé, il faudra un arbitre : un serveur Godot sans tête ou Nakama, qui rejoue le journal (graine + coups) ou tient lui-même la table.
- Le moteur reste donc pur et déterministe, et chaque partie terminée produit son journal.
- Un mélange commit-reveal empêcherait l'hôte de truquer le paquet.
- Firebase seul ne peut pas arbitrer sur l'offre gratuite : les Cloud Functions demandent l'offre Blaze.

## 7. Feuille de route (0.1.x)
1. ✅ Squelette : projet, CI (APK + Windows), ce document.
2. ✅ Moteur de Belote : donne, prise, jeu de la carte, belote, décompte. Tests.
3. Annonces.
4. Bots et parties simulées (1000 parties à graine, aucun coup illégal, les points tombent juste).
5. Table en paysage sur téléphone, jouable hors ligne contre 3 bots. Premier test de l'APK.
6. En ligne avec Tube : créer ou rejoindre par code, places, bots, retour à sa place.
7. Écran des options de règles, partagé par l'hôte.
8. Plus tard : tables publiques (Firebase), Coinche, Tarot, classement, jeu hors ligne à proximité.
