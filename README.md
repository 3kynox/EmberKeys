# EmberKeys

Keeps the key bindings that Emberveil forgets at every restart: keys whose
unshifted press produces a **non-ASCII character**. Works on Windows and
Linux, no dependencies, plays nicely with unrealUI. English UI by default,
French on frFR clients.

> **This addon is a temporary workaround.** The underlying bug has been
> reported to the Emberveil developers. Once they fix the client — possibly
> in several steps (bindings surviving a restart first, proper key names
> later) — EmberKeys does nothing useful anymore and can simply be deleted.
> If your special keys still work after a client restart *without* pressing
> them first, the fix has landed and you no longer need this addon.

## Who is affected

- **French / Belgian AZERTY**: the digit row types `é è ç à` unshifted —
  action buttons 2, 7, 9, 10 (and `²` next to `&`). This is the main victim.
- **Any layout with unshifted non-ASCII keys**, if you bind them: German or
  Nordic layouts (ü ö ä æ ø å…), Turkish (ğ ş ı…), and **Cyrillic layouts,
  where every letter key is affected**.
- **Not affected**: plain QWERTY, and Chinese/Japanese/Korean players — the
  physical keystrokes there are ASCII (IME input happens above them).

## The bug in one paragraph

The client resolves these keys to engine ids like `UNKNOWNCHARCODE_201`
(201 = É). The Unreal engine only creates such an id at the **first physical
press of the key after the client starts**. At startup, before any press,
the id does not exist yet, so the client silently drops those bindings while
loading `Keybinds.ini` — you have to re-bind them every session.

## What the addon does

- **Remembers** those bindings in its own saved variables, wherever they
  were made: the *Key Bindings* panel or unrealUI's quick bindings. Bind
  once, EmberKeys keeps it.
- **Re-applies them automatically each session.** The engine imposes one
  ritual it cannot avoid: after each client launch, every affected key must
  be **pressed once**. In practice: **sweep the affected row once** (e.g. the
  whole AZERTY digit row) — at the **character-select screen** or **in
  game**, into the void; nothing needs to be on screen. The addon lists the
  keys it is waiting for at login, confirms each re-attachment in the chat,
  and one press unlocks all chords of that key (é also unlocks alt+é).
- After a mere **relog or /reload** (client not closed), restoration is
  **instant and press-free**.
- **Fixes the button labels**: `2 7 9 0` in the hotkey corner instead of
  `UNKNOWNCHARCODE_…` (native bars) or a flickering `UNKN` (unrealUI), on
  the main bar and the multibars.

## Installation

Copy the `EmberKeys` folder into `…/Azeroth/Interface/AddOns/`, restart the
game, check the addon is ticked at the character-select screen.

On a French (frFR) client, EmberKeys pre-installs the four standard AZERTY
bindings (é→2, è→7, ç→9, à→0) on first run. Everyone else: either type
`/ek default` (AZERTY row), or just bind your keys normally in the UI — the
addon follows whatever you do.

⚠️ On Emberveil, never **untick** an addon at the character-select screen
(client bug: crash at next launch). To remove an addon, delete its folder.

## Commands

- `/ek` (or `/emberkeys`, `/azerty`) — status of remembered bindings + help
- `/ek default` — install the standard AZERTY digit-row bindings
- `/ek reset` — clear the addon's memory
- `/ek diag` — diagnostics (English, for bug reports)

## Other layouts

Capture is layout-independent: any binding on a non-ASCII key is remembered
and restored, whatever the keyboard. Presets (`/ek default <name>`) and digit
labels currently exist for French AZERTY only; contributions welcome — see
the `LAYOUT_PRESETS` table at the top of `EmberKeys.lua`.

---

# EmberKeys (français)

Rend persistants les raccourcis qu'Emberveil oublie à chaque redémarrage :
les touches qui produisent un caractère non-ASCII. Sur AZERTY : **é è ç à**
(boutons d'action 2, 7, 9, 10) et `²`. Également concernés si vous les
bindez : claviers allemands/nordiques/turcs, et les claviers cyrilliques sur
toutes les lettres. Non concernés : QWERTY pur et saisies par IME (chinois…).

**Addon temporaire** : le bug est remonté aux développeurs ; une fois le
client corrigé (peut-être en plusieurs étapes), l'addon devient inutile —
supprimez simplement son dossier. Si vos touches spéciales survivent à un
redémarrage sans avoir été pressées d'abord, le correctif est arrivé.

**Le rituel, imposé par le moteur** : après chaque lancement du client,
pressez une fois chaque touche concernée — le plus simple est d'**arroser la
rangée complète** (rangée des chiffres en AZERTY), à l'**écran de sélection
du personnage** ou **en jeu**, dans le vide. L'addon liste les touches
attendues à la connexion et confirme dans le chat ; une frappe débloque
aussi les combinaisons (é débloque alt+é). Après un simple relog ou /reload
(sans fermer le jeu) : restauration instantanée, zéro frappe.

Il corrige aussi l'affichage des boutons (`2 7 9 0` au lieu de `UNKN…`).

Sur un client en français, les quatre liaisons AZERTY standard sont posées
d'office à la première installation. Commandes : `/ek`, `/ek defaut`,
`/ek raz`, `/ek diag`. Pour retirer un addon : supprimer son dossier, ne
jamais le décocher (bug client, crash).
