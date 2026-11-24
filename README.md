# 🌀 Chaos Cam

Un script pour **OBS Studio** qui fait subir des effets absurdes à ta webcam : séisme, toupie, rebond façon logo DVD, grosse tête, caméra thermique, pop art…

Les effets se déclenchent :
- 🎮 **par tes viewers**, avec des commandes dans le chat Twitch (`!toupie`, `!chaos`…)
- ⌨️ **au clavier**, avec un raccourci par effet
- 🎲 **au hasard**, avec le mode auto qui frappe toutes les X minutes

Après chaque effet, la webcam revient exactement à sa place.

---

## 📦 Installation

### Méthode rapide (Windows)

1. Télécharge le fichier `chaos-cam-vX.Y.Z.zip` de la [dernière version](https://github.com/Th4End/obs-chaos-cam/releases/latest) et dézippe-le.
2. **Ferme OBS.**
3. Double-clique sur **`Installer Chaos Cam.bat`**.
4. Rouvre OBS : le script est déjà chargé.

L'installeur copie le script dans `%APPDATA%\obs-studio\chaos-cam\` et l'ajoute à toutes tes collections de scènes. Une sauvegarde de chaque collection est faite à côté (fichier `.avant-chaos-cam.bak`).

> Windows peut afficher un avertissement SmartScreen : clique sur *Informations complémentaires*, puis sur *Exécuter quand même*.
> Relance l'installeur après chaque mise à jour du script : il remplace l'ancienne version sans créer de doublon et garde tes réglages.

### Méthode manuelle (Windows, macOS, Linux)

Dans OBS : **Outils → Scripts → `+`**, puis choisis `chaos_cam.lua`.

---

## ⚙️ Configuration

Dans **Outils → Scripts → Chaos Cam** :

| Réglage | À quoi ça sert |
|---|---|
| **Source victime** | La source qui subit les effets, en général ta webcam |
| **Son à jouer** | *(optionnel)* une source média (« boing », klaxon…) lancée à chaque effet. Elle doit être présente dans ta scène. |
| **Durée d'un effet** | De 1 à 15 secondes (4 s par défaut) |
| **Effets mouvement / photomaton** | Coche les effets autorisés, pour le hasard comme pour le chat |
| **Tester** | Un bouton par effet pour l'essayer tout de suite |

### Chat Twitch

Coche **« Chat Twitch »** et indique le nom de ta chaîne. Le script lit le chat **en anonyme** : il n'y a ni mot de passe, ni token, ni bot à créer.

| Réglage | Par défaut |
|---|---|
| Qui peut déclencher | Tout le monde (ou abonnés/VIP/modos, ou modos seulement) |
| Délai entre deux effets | 15 s |
| Délai par viewer | 60 s |
| Texte « qui a lancé quoi » | *(optionnel)* une source Texte qui affiche « 🌀 Pseudo a lancé Toupie ! » |

Le streamer n'a jamais de délai. Les commandes fonctionnent **dès qu'OBS est ouvert**, même hors live.

### Mode auto

Déclenche un effet au hasard à un intervalle aléatoire, entre 60 et 180 s par défaut. Par défaut, il ne tourne que pendant un live ou un enregistrement.

### Raccourcis clavier

**Paramètres → Raccourcis clavier**, puis cherche « Chaos Cam ». Il y a un raccourci pour un effet au hasard et un par effet.

---

## 💬 Commandes du chat

| Commande | Effet |
|---|---|
| `!chaos` | Un effet au hasard |

### Effets mouvement

| Commande | Effet |
|---|---|
| `!seisme` | Séisme : la cam tremble dans tous les sens |
| `!toupie` | Toupie : deux tours complets |
| `!envers` | Tête en bas |
| `!grossetete` | Grosse tête : zoom ×2,6 |
| `!mini` | Mini-moi : la cam rétrécit et sautille |
| `!miroirfou` | Miroir fou : retournements gauche/droite en boucle |
| `!gelee` | Gelée : la cam gigote comme un flan |
| `!dvd` | Rebond DVD : la cam rebondit sur les bords de l'écran |
| `!laver` | Machine à laver : quatre tours en tremblant |

### Effets photomaton

| Commande | Effet |
|---|---|
| `!bulle` | Renflement (effet loupe) |
| `!creux` | Creux (visage pincé) |
| `!tourbillon` | Tourbillon |
| `!compresse` | Compression horizontale |
| `!etire` | Étirement vertical |
| `!jumeau` | Miroir : la moitié gauche reflétée |
| `!tunnel` | Tunnel de lumière |
| `!fisheye` | Fish-eye |
| `!kaleido` | Kaléidoscope |
| `!thermique` | Caméra thermique |
| `!rayonx` | Rayons X |
| `!bd` | Bande dessinée |
| `!popart` | Pop Art : quatre copies en couleurs façon Warhol |
| `!croquis` | Croquis au crayon |
| `!bdsm` | Donjon : cuir, barreaux, bandeau « censuré » et coups de fouet. **Désactivé par défaut.** |

Les accents sont acceptés (`!séisme`, `!gelée`…).

---

## ❓ FAQ

**Ça marche avec Iriun Webcam, Camo, une webcam USB… ?**
Oui, avec n'importe quelle source vidéo d'OBS. Pour Iriun, lance l'application sur le PC et le téléphone **avant** OBS.

**Rien ne se passe quand je tape une commande.**
Ouvre « Journal du script » en bas de la fenêtre Scripts. Tu dois y voir `Twitch : connecté au chat de …`. Vérifie aussi que l'effet est coché, que ta source victime est bien dans la scène affichée et que le délai est écoulé.

**L'effet ne s'applique pas à ma cam.**
Pour les effets mouvement, la source victime doit être présente dans la scène **en cours**.

**Le chat Twitch marche sur Mac et Linux ?**
Pas pour l'instant : la connexion au chat utilise les sockets de Windows. Les effets, les raccourcis et le mode auto, eux, marchent partout.

**Les points de chaîne ou les bits déclenchent des effets ?**
Pas encore : il faudrait connecter ton compte Twitch, alors que le script lit le chat en anonyme.

---

## 🗑️ Désinstallation

1. **Outils → Scripts**, sélectionne Chaos Cam, puis clique sur `−`.
2. Dans les filtres de ta webcam, supprime le filtre **« Chaos Cam FX »**.
3. *(optionnel)* Supprime le dossier `%APPDATA%\obs-studio\chaos-cam\`.

---

## 📁 Contenu

| Fichier | Rôle |
|---|---|
| `chaos_cam.lua` | Le script OBS : effets, shader photomaton, chat Twitch |
| `Installer Chaos Cam.bat` | L'installeur en double-clic pour Windows |
