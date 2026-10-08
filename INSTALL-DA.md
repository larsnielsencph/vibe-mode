# VibeMode — installationsguide til Lars

Denne guide er skrevet, så du kan bygge og køre appen på din egen MacBook Air (Apple Silicon, macOS 14 eller nyere) med Xcode. Du behøver ikke en betalt Apple Developer-konto.

## Hvad appen gør

VibeMode bor i menulinjen (ingen Dock-ikon).

- **Normal mode** — Mac’en sover, når du klapper låget i, præcis som standard-macOS. Når du skifter tilbage til Normal, gendannes den oprindelige `SleepDisabled`-værdi, og alle keep-awake-hold slippes.
- **Vibe mode** — Mac’en bliver vågen med lukket låg, netværk (Wi-Fi / iPhone-hotspot) holdes i live, og alle almindelige apps bliver bedt om at afslutte **undtagen** din allowlist (Claude, Cursor, Terminal, iTerm2, Warp, Ghostty som udgangspunkt) plus alt, der lytter på en lokal TCP-port (dev-servers).

Ikonet skifter: måne = Normal, lyn = Vibe.

## 1. Installer Xcode

1. Åbn **App Store** på Mac’en.
2. Søg efter **Xcode** og installer (det er stort; giv det tid).
3. Åbn Xcode én gang, acceptér licensen, og lad den installere *Additional Components*.
4. Tjek i Terminal:

```bash
xcode-select -p
swift -version
```

Hvis `xcode-select` peger forkert:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 2. Hent projektet

Hvis du har mappen som et git-checkout, er du allerede i mål. Ellers: åbn den mappe, der indeholder `VibeMode.xcodeproj`.

## 3. Åbn projektet i Xcode

1. Dobbeltklik på `VibeMode.xcodeproj` **eller** i Terminal:

```bash
open VibeMode.xcodeproj
```

2. Øverst i værktøjslinjen: scheme **VibeMode**, destination **My Mac** (ikke et iOS-simulator-navn, ikke “Any Mac”).
3. Signing er sat til **ad-hoc / Sign to Run Locally** (`CODE_SIGN_IDENTITY = "-"`), så appen kan køre på den Mac, der bygger den, uden Team.

Hvis Xcode nægter at køre med ad-hoc:

1. Klik på projektet **VibeMode** i venstre kolonne → target **VibeMode** → **Signing & Capabilities**.
2. Sæt flueben i **Automatically manage signing**.
3. Team: din **Personal Team** (din Apple ID). Det er gratis.
4. Fjern **App Sandbox**, hvis Xcode tilføjer det. Appen **skal** være uden sandbox, ellers kan den ikke afslutte andre apps eller kalde `pmset`.

## 4. Byg og kør

1. **Product → Run** (⌘R).
2. Første gang kan macOS spørge, om du vil åbne en app fra en oidentificeret udvikler. Tillad det (Systemindstillinger → Privatliv og sikkerhed, hvis nødvendigt).
3. Der kommer **ikke** et vindue. Kig i menulinjen efter et **måne**-ikon (`moon.zzz`).
4. Tillad **notifikationer**, når macOS spørger — de bruges til batteri, varme og “gendannet efter sidste session”.

Hvis ikonet mangler: klik **»** i menulinjen (Control Center) og træk VibeMode ud, eller kør igen fra Xcode og se Console for fejl.

## 5. Første gang du slår Vibe til (admin-adgangskode)

1. Tilslut gerne iPhone-hotspot **før** du klapper låget (Mac’en skal allerede være på nettet).
2. Klik på ikonet → **Vibe mode**.
3. Du får en liste over apps, der vil blive bedt om at Quit. Gennemgå den. Sæt flueben i **Don’t ask again**, hvis du er tilfreds. Finder, systemprocesser, VibeMode, allowlisten og processer med en lokal TCP-port bliver **ikke** rørt.
4. macOS viser den almindelige dialog **“osascript wants to make changes”** / administrator-adgangskode. Det er `pmset -a disablesleep 1`. Adgangskoden gemmes **ikke** i appen; macOS cacher den kortvarigt.

Uden adgangskode prøver appen stadig den usignerede IOKit-lid-override. Den er bedre end ingenting, men **SleepDisabled er den pålidelige metode** til lukket låg i en taske. Giv admin-adgang.

5. Ikonet skifter til et **lyn**. Statuslinjen viser batteri og hvilke processer der holdes i live.

## 6. Anbefalet: passwordfri toggle + boot-sikkerhedsnet

`SleepDisabled` **overlever reboot**. Hvis appen crasher, og du aldrig får den startet igen, kan Mac’en nægte at sove, indtil nogen kører undo-kommandoen.

I appen: **Settings → Power → Install password-free toggle + boot safety net**.

Det (efter én admin-adgangskode):

- Lægger en **visudo-tjekket** fil i `/etc/sudoers.d/vibemode`, som **kun** tillader  
  `/usr/bin/pmset -a disablesleep 0` og `/usr/bin/pmset -a disablesleep 1`  
  for gruppen `admin`. Ikke vilkårlig `pmset`, ikke andre kommandoer.
- Installerer LaunchDaemon `dk.lars.vibemode.safetynet`, som ved **hver boot** kører `pmset -a disablesleep 0`.

Samme ting fra Terminal, hvis du vil læse scriptet først:

```bash
less scripts/install-passwordless-pmset.sh
sudo bash scripts/install-passwordless-pmset.sh
sudo -n pmset -a disablesleep 0 && echo OK
```

## 7. Daglig brug

Typisk flow, når du går:

1. Cursor / Claude / terminaler kører. Dev-server lytter på en port.
2. Tilslut iPhone-hotspot.
3. Vibe mode → bekræft quit-listen.
4. Klap låget. Mac’en skal blive ved med at trække strøm (ventilator kan køre). Læg den et sted med lidt luft, ikke under dynen.
5. Når du er hjemme: åbn låget, **Normal mode**. Slack og Safari starter du selv igen.

Andet:

- **Settings → Allowlist → Add app…** hvis du også vil beholde f.eks. Docker Desktop eller Xcode.
- **Launch VibeMode at login** — anbefales, så en uren session bliver rettet efter reboot.
- Batteri-grænse (standard 15 %): under den går Mac’en automatisk tilbage til Normal og sender en notifikation.
- Varme: warning ved høj termisk tilstand; valgfri auto-Normal ved *critical*.

## 8. Stop altid sikkert

- Klik **Normal mode**, eller **Quit VibeMode**. Begge gendanner søvn.
- Nødbremse i Terminal:

```bash
sudo pmset -a disablesleep 0
pmset -g | grep -i SleepDisabled
```

Du vil se `SleepDisabled 0` (eller linjen kan mangle — det er også “slået fra”).

Der ligger en kopi i `scripts/emergency-restore-sleep.sh`.

## 9. Læg appen i Programmvinduet

Når du er tilfreds:

1. I Xcode: **Product → Build** (⌘B).
2. I venstre kolonne: **Products → VibeMode.app** → højreklik → **Show in Finder**.
3. Træk `VibeMode.app` til `/Programmer` (Applications).
4. Åbn derfra fremover. Slå **Launch at login** til i Settings.

Lad Xcode-debug-sessionen køre, mens du tester; når du quitter Xcode, dør den kørende debug-app.

## 10. Afinstallation

1. Sæt **Normal mode**. Quit VibeMode.
2. Settings → Power → **Remove helper** (hvis du installerede sudoers/daemon) **eller**:

```bash
sudo launchctl bootout system /Library/LaunchDaemons/dk.lars.vibemode.safetynet.plist
sudo rm -f /Library/LaunchDaemons/dk.lars.vibemode.safetynet.plist
sudo rm -f /etc/sudoers.d/vibemode
sudo pmset -a disablesleep 0
```

3. Slet `VibeMode.app` og evt. `~/Library/Application Support/VibeMode`.

## Fejlfinding

| Symptom | Hvad du gør |
|---|---|
| Mac sover stadig med lukket låg | Gav du admin-adgang? Tjek `pmset -g` for `SleepDisabled 1`. Uden den linje på `1` er det kun IOKit-fallback. |
| macOS spørger om adgangskode hver gang | Installer helper’en i punkt 6. |
| Apps blev ikke afsluttet | De kan have et “Gem?”-ark. VibeMode tvinger dem ikke. Tilføj dem til allowlisten, eller gem først. |
| Hotspot falder | Forbind hotspot **før** låg. Hold iPhone tæt på. VibeMode kan ikke holde et netværk, Mac’en aldrig joinede. |
| Mac’en er varm i tasken | Forventeligt. Skift til Normal, eller hæv luft / sænk load. Auto-Normal ved lavt batteri og critical heat. |
| Efter crash sover Mac’en ikke | `sudo pmset -a disablesleep 0`. Installer boot-sikkerhedsnettet. Åbn VibeMode — den gendanner Normal ved start. |
| “Operation not permitted” når den quitter apps | App Sandbox er slået til. Slå den fra (punkt 3). |
| Intet menulinje-ikon | Appen er `LSUIElement` (ingen Dock). Kig i menulinjen, eller Control Center → menulinje-ikoner. |

## Hvorfor admin overhovedet?

`caffeinate` og Amphetamine stopper *inaktivitetssøvn*. De stopper **ikke** søvn, når du klapper låget i. Det flag, der gør det pålideligt på nuværende macOS, er `pmset disablesleep` / `SleepDisabled`, og det kræver root. Alternativet — en SMAppService-hjælpeprocess — er pænere i en notariseret App Store-app, men fejler typisk for et projekt, du selv bygger i Xcode uden Developer ID. Derfor: én adgangskode, valgfri smal sudoers-regel, og et boot-script der slukker flaget, hvis noget går galt.
