# Audit di sicurezza — The Last Gallon 0.1.0 (2026-11-05)

Audit del codice del mod (Lua, Kahlua), della sua superficie multiplayer e
del flusso dei dati persistenti, con prove eseguite negli ambienti locali di
test del repository (suite Kahlua e harness multiplayer su questo computer).
Durante l'audit nessun file del pacchetto runtime (`Contents/`) è stato
modificato: le prove sono file separati (`tests/audit/`,
`TLGHarness/AuditCases.lua`, due sonde in `MPServer.lua`, l'opzione
`-Only audit` del launcher) e questo report.

**Aggiornamento dopo la consegna (2026-11-05).** Su richiesta del
proprietario sono state applicate le correzioni di V-02 e V-03. V-03 è
corretta in modo diverso da quanto proposto nella prima versione, che non
avrebbe protetto nulla (errata in §7, V-03 punto 7). Le prove delle
correzioni sono in §7.2.

## 1. Sintesi dei rischi e priorità d'intervento

Il mod è progettato come "server-authoritative": ogni mutazione passa da un
comando `TLG` gestito sul server, con validazione dei riferimenti, controlli
di portata, ledger anti-replay e revisioni. L'analisi conferma che questa
parte è fatta con cura: non sono emerse esecuzioni di codice, path traversal,
chiamate di sistema, né crash del server provocabili da un client. I rischi
trovati sono di integrità del gioco e di riservatezza in multiplayer, e il
più importante è un limite del motore che il progetto del mod non tiene in
conto.

| Priorità | ID | Rischio | Stato della prova |
| --- | --- | --- | --- |
| 1 | V-01 | Gli store in cui il mod tiene lo stato autoritativo (modData di item, oggetti del mondo, progetti di conversione) sono riscrivibili da qualunque client: il motore 42.21 applica sul server i pacchetti `SyncItemFields` e `ObjectModData` inviati dai client. Un client modificato riscrive condizione e composizione del carburante, forgia conversioni "Commissioned", stati macchina e usura. | **Dimostrata nel runtime** (run 1 e 2, giocatore con ruolo `user`): sidecar della tanica, record della pompa e progetto di conversione del generatore riscritti sul server; bytecode dei pacchetti (§3) |
| 2 | V-03 | Il record mondo `TLG_World` è inviato a ogni client che lo chiede e contiene `machineSites`: le coordinate di ogni macchina con un lotto in corso (fino a 256), più il seed del mondo. Su un server PvP rivela le basi. | **Dimostrata nel runtime** (run 1). **Corretta** dopo la consegna: i campi privati sono nello store del server (§7.2) |
| 3 | V-02 | Il comando `status` non applica il controllo di portata: un client legge livello, composizione e valutazione del carburante di qualunque veicolo, pompa o generatore caricato, ed enumera gli id dei veicoli. | **Dimostrata nel runtime** (run 2: auto a 35 tile, pompa e generatore a ~25 tile) e nei test Kahlua. **Corretta** dopo la consegna, tranne l'enumerazione degli id (§7.2) |
| 4 | V-09 | I comandi non considerano le safehouse né chi ha avviato un lavoro: `conversion.cancel` e `conversion.remove` consegnano al richiedente le parti che un altro giocatore aveva fornito; `machine.collect`, `machine.abort`, `machine.loadWash` agiscono sulle macchine di chiunque entro 2–2.5 tile, anche attraverso un muro. | Analisi statica; test Kahlua per il recupero parti |
| 5 | V-05 | Con l'opzione sandbox `FuelStationGasInfinite` il record del serbatoio si svuota mentre la pompa resta infinita; da quel momento ogni erogazione vanilla a quella pompa viene annullata dal wrapper del mod (il carburante erogato sparisce). Raggiungibile dal gioco normale, non solo da un client modificato. | Test Kahlua con il wrapper reale del mod su oggetti mock; runtime NOT RUN |
| 6 | V-04 | `transfer` accetta qualunque coppia di estremi (pompa→auto, pompa→tanica, generatore→tanica, auto→tanica) in modo istantaneo, senza azione a tempo, senza tubo per sifonare e senza controllo della corrente alla pompa (il motore la richiede solo per inizializzare una pompa mai usata). | **Dimostrata nel runtime** (run 2: 5 L dalla pompa alla tanica in una richiesta) e nei test Kahlua (tutte le coppie) |
| 7 | V-06/V-07 | Nessuna validazione dei record persistenti: un record con `t` molto nel passato o con quantità negative/NaN (forgiato via V-01 o da un salvataggio corrotto) costa un segmento climatico per giorno a ogni lettura (nessun limite) o fa fallire ogni lettura successiva dell'oggetto. | Test Kahlua (costo lineare misurato) |
| 8 | V-10 | Il mod di sviluppo `TheLastGallonHarness` espone comandi server senza controllo di privilegio (item, livelli, veicoli). Non è nel pacchetto (verificato), ma va tenuto fuori da qualsiasi server pubblico. | Verifica del pacchetto e del launcher |

Interventi consigliati, in ordine: (1) copia autoritativa server-only dei
record e dei progetti con riconciliazione alla lettura (V-01, V-07);
(2) separare dal record mondo trasmesso ciò che serve solo al server (V-03,
fatto); (3) controllo di portata in `status` (V-02, fatto); (4) proprietà/safehouse per
cancel/remove e per i comandi macchina, parti restituite al proprietario
(V-09); (5) ricarica del record quando la pompa è infinita (V-05); (6) lista
bianca delle coppie di `transfer`, controllo corrente e tubo (V-04); (7) clamp
dell'intervallo e `Supply.check` alla lettura (V-06/V-07).

## 2. Perimetro

| Voce | Valore |
| --- | --- |
| Repository | `mods/TheLastGallon`, commit `66e4685` (2026-11-05 00:03 +01:00); il pacchetto runtime `Contents/` è identico a HEAD (le modifiche non committate riguardano documenti, harness e launcher) |
| Versione del mod | 0.1.0 (`42/mod.info`, `TLG.VERSION`) |
| Gioco | Project Zomboid **42.21.0** (`4a0e9546ec`), `projectzomboid.jar` installato; class file Java 25; Kahlua (Lua 5.1 subset, `%` Java, niente `next`/`math.random`) |
| Modalità considerate | single player (gestori chiamati in locale), server dedicato con client (`OnClientCommand`/`sendServerCommand`), host cooperativo (il server è un processo separato: stesso caso del dedicato) |
| Configurazioni | opzioni sandbox del mod (`sandbox-options.txt`: CampaignSpeed, ExistingSavePolicy, TransitionDays, ProtectIncompatiblePours, VehicleStalls, StationContamination) e vanilla `FuelStationGasInfinite`, `ElecShutModifier`, `AllowExteriorGenerator` |
| Ambienti di prova | suite Kahlua sulla VM del gioco (`tools/run-tests.ps1`, mock in `tests/audit/mocks.lua`); harness MP (`tools/run-mp-harness.ps1 -Clients 1 -Only audit -NonAdmin`): server dedicato TLGDev e un client, account `tlga` con ruolo `user`, mondo nuovo ad ogni run, cache isolate sotto `%LOCALAPPDATA%\TheLastGallon` |
| Evidenze bytecode | `javap` (Corretto 17) su `projectzomboid.jar`: `GlobalModData`, `GlobalModDataPacket`, `ObjectModDataPacket`, `SyncItemFieldsPacket`, `SyncItemModDataPacket`, `ReceiveModDataPacket`, `InventoryItem.syncItemFields`, `BaseVehicle.transmitPartModData`, `IsoObject.getPipedFuelAmount`, `PacketTypes$PacketType` |

## 3. Contesto tecnico

**Dove gira il codice.** `media/lua/shared/TLG/**` carica su client e server.
`client/TLG/**` (menu, `Client/Net.lua`) solo sul client; `server/TLG/**`
(`Server/Net.lua`, `Loot.lua`; dopo la correzione di V-03 anche `Server/WorldStore.lua`) solo sul server. L'autorità è decisa a runtime
da `TLG.World.isAuthority()` (= `isServer() or not isClient()`): in single
player il client è autorità e `TLG.Net.request` chiama `Handlers.dispatch` in
locale; in multiplayer il client invia `sendClientCommand(player, "TLG",
command, args)` e il server risponde con `sendServerCommand(player, "TLG",
"reply", res)`. Le azioni a tempo (`ISTLGPourFuel`, `ISTLGConversionWork`) in
MP sono ricostruite dal server (`NetTimedAction`) che ne esegue `complete()`;
la pour chiama lì `Handlers.dispatch("transfer")`.

**Persistenza.** Record carburante ("sidecar" `tlg`) nel modData di item,
oggetti del mondo (pompe, generatori) e parti veicolo; progetti di conversione
`tlgConv` nel modData del generatore o della parte Engine; stato macchina
`tlgProc` nel modData dell'item macchina; record mondo `TLG_World` nel ModData
globale (seed, nextId, calendario, log climatico, storia dei profili,
`machineSites`). Conoscenza del giocatore in `player:getModData().tlgKnowledge`.

**Trasporto dal motore (verificato nel bytecode 42.21.0).**

* `ClientCommand` richiede solo la capability `LoginOnServer`: ogni giocatore
  connesso raggiunge `OnClientCommand`. `args` è sempre una `KahluaTable` o
  nil (firma Java), mai un altro tipo.
* `GlobalModDataPacket.parse` crea una nuova tabella, la carica e scatena
  `OnReceiveGlobalModData(key, table)`; **non** scrive in `GlobalModData`.
  Il gestore del mod (`World.onReceive`) scrive solo quando `isClient()`: il
  server ignora i tentativi dei client (confermato in run 2, AUD-2b).
  `GlobalModData.receiveRequest` risponde a qualsiasi client con la tabella
  completa della chiave richiesta.
* `SyncItemFieldsPacket.parse` risolve l'item (`ContainerID` →
  `getItemWithID`) e carica su di esso **il FluidContainer e il modData** già
  in `parse`, su entrambi i lati; `InventoryItem.syncItemFields()` lato client
  invia questo pacchetto. `SyncItemModDataPacket.parse` fa lo stesso per il
  solo modData.
* `ObjectModDataPacket.parse` carica il modData ricevuto nell'`IsoObject`
  (o lo azzera con `wipe()` se il flag è falso); `processServer` lo ritrasmette
  ai client vicini. `IsoObject.transmitModData()` lato client invia questo
  pacchetto. Nessun controllo di capability o di anti-cheat nel pacchetto
  (`isConsistent` verifica solo che l'oggetto esista).
* `BaseVehicle.transmitPartModData` agisce solo quando `GameServer.server`:
  il modData delle parti veicolo (record del serbatoio, `tlgConv` del motore)
  non è scrivibile dai client per questa via.
* `IsoObject.getPipedFuelAmount()`: con `FuelStationGasInfinite` restituisce
  1000; una pompa mai inizializzata (nessun `fuelAmount` nel modData) è
  inizializzata solo se il suo quadrato ha corrente (`haveElectricity` con
  `AllowExteriorGenerator`, oppure `hasGridPower`), altrimenti riporta nulla;
  una pompa già inizializzata riporta le sue unità anche senza corrente.

**Vanilla, per confronto.** Il rifornimento dell'auto dalla pompa è offerto
dal menu solo con corrente (`ISVehicleMenu.lua:1088`), ma
`ISRefuelFromGasPump:isValid` controlla solo l'area del tappo; il sifone
richiede un oggetto con tag `base:siphongas`; le azioni durano in proporzione
ai litri. Il server non esegue `isValid` delle azioni Lua dei client
(`NetTimedAction.isValid` è falso, docs/engine-capabilities.md G07).

## 4. Inventario delle superfici esposte

| Superficie | Ingresso | Controlli presenti | Mancanze |
| --- | --- | --- | --- |
| `transfer` | `OnClientCommand` → `H.transfer` → `Tx.transfer` | `validateRequest` (requestId stringa ≤64, `amount` finito in (0, 1e5]), riferimenti risolti e validati sul server, `canAccess` su entrambi gli estremi (inventario proprio; 2.5 tile; 3.5 tile pompa; area tappo veicolo), ledger per attore, revisioni attese, bound su sorgente/room/riserve, compatibilità salvo `experimental` | nessuna lista di coppie ammesse; nessuna azione a tempo né tubo; nessun controllo corrente/safehouse; `experimental` deciso dal client (V-04, V-08, V-09) |
| `sample`, `treat` | idem → `openTarget` | come sopra più consumo item dall'inventario del richiedente; `op` da lista fissa | — |
| `status` | `H.status` | riferimento risolto; dopo la correzione `canObserve` o `canAccess` dell'endpoint | era **senza `canAccess`** (V-02, corretta); un id inesistente risponde ancora `unknown_target` |
| `machine.*` (9 comandi) | `MachineHandlers` → `machineState` | validateRequest, ledger, item macchina trovato sul quadrato indicato o nel proprio inventario, distanza ≤2.5, `isPlaced` per ogni mutazione, quantità limitate dal dominio (`Process.plan`), ingredienti presi dall'inventario del richiedente | nessuna proprietà/safehouse; `loadWash` prende il wash dal fermentatore di chiunque entro 2 tile; `collect` imbottiglia l'output di chiunque (V-09) |
| `conversion.*` (7 comandi) | `ConversionHandlers` → `run` | validateRequest, ledger, device risolto e in portata (4 tile veicolo, 2.5 generatore), attore (abilità, ricette, inventario) letto sul server, macchina a stati del dominio, revisioni | `cancel`/`remove` di chiunque, parti restituite al richiedente (V-09); `args.conversion` validato solo dal registro (ok) |
| Azioni a tempo in MP | `ISTLGPourFuel.complete` (server), `ISTLGConversionWork` (solo report) | la pour ridispaccia `transfer` con gli stessi controlli; il lavoro accredita al massimo 1 h per report (`WORKER_TIMEOUT_HOURS`), tempo letto sul server | — |
| ModData globale | `ModData.request/transmit` (motore) | il server ignora le tabelle ricevute; risponde però a una richiesta per qualunque chiave | `TLG_World` intero inviato ai client (V-03, corretta: i campi privati sono ora nello store del server, `gos_tlgworld.bin`) |
| modData di item/oggetti | `SyncItemFields`, `SyncItemModData`, `ObjectModData` (motore) | nessuno del mod: i record sono letti e creduti (`Migrations.sidecar` controlla solo `v`) | V-01, V-07 |
| Wrapper di azioni vanilla | `ISTakeFuel`, `ISRefuelFromGasPump`, `ISAddGasolineToVehicle`, `ISTakeGasolineFromVehicle`, `ISAddFuel`, `ISTakeGenerator`, drop/unequip, `FluidContainer.Transfer` | tutto in `pcall`, solo sull'autorità | V-05 (stazione infinita) |
| Eventi periodici (server) | `EveryHours` (clima + `sampleSites` ≤256 siti), `EveryTenMinutes` (`observeFires`), `EveryOneMinute` (veicoli nella cella) | limiti espliciti, `pcall` | — |
| Script di gioco | `TLG_items.txt`, `TLG_machines.txt`, `TLG_fluids.txt` | ricette con input vanilla verificati; `OnCreate` del manuale imposta solo `printMedia` | — |
| Harness di sviluppo | modulo `TLGH` (`MPServer.lua`) | nessuno | V-10 |

Non esistono nel mod: valutazione dinamica di codice, `loadstring` su input,
accessi al filesystem (solo l'harness scrive file di risultato in
`<cache>/Lua`), bridge Java oltre le API di gioco, integrazioni esterne,
webhook, credenziali nel pacchetto (verificato: `dist/`, `package.ps1`, grep
su `password|token|webhook|secret|api key`; le credenziali dell'harness MP
stanno in `.devcache`/`mpserver\dev-credentials.txt`, ignorati da git e mai
stampati).

## 5. Scenari di attacco e capacità iniziali

| Scenario | Capacità necessarie | Cosa aggiunge il mod |
| --- | --- | --- |
| A. Giocatore senza privilegi con client modificato (invia comandi `TLG` arbitrari) | account sul server; nessun admin | V-02 (lettura a distanza; corretta, §7.2), V-04 (trasferimenti istantanei e combinazioni non previste), V-09 (lavori e macchine altrui), V-08 (`experimental`) |
| B. Lo stesso client usa i pacchetti di sync del motore (`syncItemFields`, `transmitModData`) | come A; il motore 42.21 li applica senza controlli | V-01: non è un'escalation oltre ciò che il motore già concede (il client può già riempire una tanica di qualunque fluido), ma rende carta straccia le garanzie del livello di autorità e abilita abusi silenziosi (conversioni gratis, carburante perfetto, output macchina) |
| C. Giocatore onesto | nessuna | V-05 (server con pompe infinite), V-03 (riceveva le coordinate delle macchine altrui senza fare nulla; corretta, §7.2) |
| D. Salvataggi o modData manipolati | accesso ai file del server, oppure B | V-06, V-07 |
| E. Server malevolo verso i client | nessuna | nessuna superficie rilevante: le risposte sono dati mostrati in finestre di testo; i gestori client sono in `pcall` |
| F. Dipendenze compromesse | — | nessuna dipendenza esterna; nessun download; pacchetto costruito da `package.ps1` con manifesto SHA-256; nessun codice offuscato trovato |

## 6. Tabella delle vulnerabilità

| ID | Titolo | Gravità | Sfruttabilità | Confidenza | Stato |
| --- | --- | --- | --- | --- | --- |
| V-01 | Stato autoritativo in store riscrivibili dal client (item e oggetti) | Media (integrità MP; alta rispetto al modello dichiarato) | alta: un client modificato, nessun privilegio | alta (runtime item, pompa e generatore; bytecode) | dimostrata nel runtime |
| V-03 | `machineSites` e seed inviati a ogni client | Media su PvP, bassa su coop | alta: `ModData.request` o il solo avvio del gioco | alta | dimostrata nel runtime; corretta (§7.2) |
| V-02 | `status` senza controllo di portata | Media-bassa (riservatezza) | alta | alta | dimostrata nel runtime (run 2) e in Kahlua; corretta (§7.2) |
| V-09 | Nessuna proprietà/safehouse; salvataggio delle parti al richiedente | Media (furto/griefing MP) | media: abilità e attrezzi del lavoro; vicinanza | alta (statica) | supportata dall'analisi statica |
| V-05 | Record del serbatoio svuotato con pompa infinita → erogazioni annullate | Media (disponibilità; solo con `FuelStationGasInfinite=true`) | alta, anche senza attaccante | media (mock + wrapper reale; runtime NOT RUN) | supportata dall'analisi; verifica in gioco necessaria |
| V-04 | `transfer` generico, istantaneo, senza tubo né corrente | Bassa-media (integrità) | alta | alta | dimostrata nel runtime (run 2) e in Kahlua |
| V-06 | Nessun limite all'intervallo di `Climate:segments`/`Aging.advance` | Bassa (disponibilità; richiede V-01 o file manipolati) | media | alta | misurata (Kahlua) |
| V-07 | Record persistenti creduti senza validazione dei campi | Bassa (disponibilità locale/log) | media | alta | statica |
| V-08 | `experimental` deciso dal client vince su `ProtectIncompatiblePours` | Bassa (hardening) | alta | alta | statica |
| V-10 | Harness: comandi server senza privilegio | Bassa (solo se installato su un server) | — | alta | verificato non distribuito |

## 7. Dettaglio delle vulnerabilità

### V-01 — Stato autoritativo in store riscrivibili dal client

1. **ID/gravità/confidenza.** V-01; Media. Alta confidenza: dimostrata nel
   runtime per gli item (run 1 e 2) e per gli oggetti del mondo, pompa e
   generatore (run 2), da un giocatore con ruolo `user`; il bytecode dei
   pacchetti spiega il meccanismo (§3).
2. **File.** `TLG/Integration/Containers.lua:90-136` (`C.read` crede il
   sidecar `tlg` di item e oggetti), `Stations.lua:57-90` (`S.read`),
   `Generators.lua:79-103` (`G.read`), `ConversionDevices.lua:80-92`
   (`CD.project`/`CD.effective` da `md.tlgConv`), `Machines.lua:104-113`
   (`M.read` da `tlgProc`), `Persistence/Migrations.lua:41-69` (solo `v`).
3. **Attaccante.** Giocatore senza privilegi con client modificato (o una
   console Lua lato client): `item:getModData().tlg = …; item:syncItemFields()`
   per gli item nel proprio inventario; `obj:getModData().tlgConv = …;
   obj:transmitModData()` per pompe e generatori nel proprio raggio di
   caricamento.
4. **Causa e percorso.** Il motore applica `SyncItemFields` (fluidi e modData
   dell'item) e `ObjectModData` (modData dell'oggetto) in `parse`, prima di
   qualsiasi `processServer`, senza capability né anti-cheat; il mod legge
   questi store come verità (`Migrations.sidecar` verifica solo che `v == 1`).
   Percorso: pacchetto del client → modData sul server → `C.read`/`S.read`/
   `G.read`/`CD.project`/`M.read` → valutazione motore, profilo, output.
5. **Impatto.** Carburante "perfetto" (deg 0, stab 2) in taniche, pompe e
   generatori; composizione della stazione senza acqua; conversione
   `Commissioned` senza parti, ore né abilità (`G.profile` → flex; test
   Kahlua); stato macchina `OutputReady` con output arbitrario da
   imbottigliare con `machine.collect` (che scrive fluidi reali); `tlgWear`
   azzerato. Con il flag falso del pacchetto `ObjectModData` il client azzera
   l'intero modData dell'oggetto (anche il `fuelAmount` vanilla della pompa,
   che il gioco re-inizializza a caso: ricarica infinita delle stazioni; è
   motore, non mod). Le parti veicolo non sono esposte (vedi §3).
   Soggetti: tutti i giocatori del server (economia del carburante); il
   server (nessun crash).
6. **Prova.** Runtime, run 1 (`docs/evidence/2026-11-05_audit_mp_run1_client_a.txt`
   e `_server.txt`): il client A (`role=user`) chiede `sample` sulla tanica
   (il server crea il record), poi scrive `deg.gasoline=7.7777`, `stab=1.5`,
   `audit=forged` nel proprio modData e chiama `syncItemFields()`; la sonda
   `probe_item` del server riporta
   `sidecar={audit=forged,…,deg={gasoline=7.7777},…,stab=1.5000,…}` →
   `PASS AUD4_item_sidecar_rewritten_by_client`. Run 2 (§7.1): lo stesso per
   la tanica; per la pompa (`transmitModData()` dal client) il server perde
   acqua e sedimento dal record della stazione e ha `deg 0`; per il generatore
   un `tlgConv` Commissioned forgiato porta `probe_generator` a
   `profile=generator_si_flex`. Kahlua (`tests/audit/test_audit.lua`,
   "forged in generator mod data" e "forged in item mod data"): la logica del
   mod che crede lo store.
7. **Correzione proposta.** Copia autoritativa server-only con
   riconciliazione alla lettura. Schema minimo:

   ```lua
   -- TLG/Authority/Vault.lua (nuovo; solo sull'autorità)
   TLG.Authority.Vault = {}
   local Vault = TLG.Authority.Vault
   Vault.KEY = "TLG_Vault"             -- ModData globale mai trasmesso
   function Vault.get(kind, id)  return ModData.getOrCreate(Vault.KEY)[kind .. ":" .. tostring(id)] end
   function Vault.put(kind, id, rec) ModData.getOrCreate(Vault.KEY)[kind .. ":" .. tostring(id)] = TLG.Tables.deepCopy(rec) end
   ```

   In `C.read`, `S.read`, `G.read`, `V.read` (dopo `Migrations.sidecar`):

   ```lua
   if persist and side and side.id then
       local own = TLG.Authority.Vault.get("supply", side.id)
       if own == nil or own.rev ~= side.rev or not TLG.Tables.deepEqual(own, side, 1e-9) then
           side = own   -- il sidecar è solo una cache: vince la copia del server
           -- own == nil: record sconosciuto al server -> trattare come assente
       end
   end
   ```

   e in ogni scrittura (`C.writeSidecar`, `S.writeSidecar`, `G.writeSidecar`,
   `V.writeSidecar`, `CD.store`, `M.write`) `Vault.put(kind, id, rec)` prima
   della copia nel modData. Per `tlgConv` e `tlgProc` lo stesso, con chiave
   l'id del progetto/processo. Costo: un deepCopy per scrittura; i record
   sono piccoli (i processi con 480 letture vanno confrontati per `rev`
   soltanto). Gli id (`World.newId`) sono già allocati solo dall'autorità,
   quindi un record con id ignoto al vault è per definizione forgiato.
   Nota: la copia server-only vive nel save del server (`GlobalModData`), che
   la versione corrente già usa per `TLG_World`.
8. **Test di regressione.** (a) Kahlua: `tests/audit/test_audit.lua` "forged
   in item mod data" deve diventare "il record riletto è quello del vault"
   (deg invariato, `stab` invariato). (b) Harness: `AuditCases.lua` AUD-4
   deve passare al contrario (`probe_item`/`probe_fuel`/`probe_generator`
   riportano i valori del server, non quelli inviati). (c) Legittimo: la
   suite esistente (`run_all.lua`) e i casi MP `fuel`, `conversion`,
   `stills` devono restare verdi: pour, sample, stabilize, conversioni,
   collect.
9. **Dipendenze.** Build 42.21.0 (bytecode); un cambiamento del motore nei
   pacchetti di sync la renderebbe irrilevante. Mod terzi che scrivono i
   modData non sono coinvolti.

### V-02 — `status` senza controllo di portata

1. V-02; Media-bassa; confidenza alta (Kahlua; run 2 nel runtime).
2. `TLG/Authority/Handlers.lua:144-155` (`H.status`): risolve il
   riferimento e legge l'endpoint; a differenza di `openTarget` (`:57`) non
   chiama `ep:canAccess(player)`.
3. Giocatore senza privilegi con client modificato: `sendClientCommand(p,
   "TLG", "status", { requestId = "x", target = { kind = "vehicle", id = n } })`
   per ogni `n`; `{ kind = "pump"|"generator", x, y, z, index }` per oggetti.
4. Il riferimento del veicolo è un id globale (`getVehicleById`); gli oggetti
   sono risolti da coordinate su qualunque quadrato caricato dal server (che
   carica l'intorno di tutti i giocatori). La risposta include `total`,
   `cap`, `primary`, `sealed`, `rev` e la valutazione del motore (`grade`,
   `reasons`, `startFactor`). Un id inesistente risponde `unknown_target`
   (`detail = no_vehicle`), uno esistente risponde: enumerazione.
   Effetto collaterale: per i generatori `ep:read()` chiama `G.chargeWear`
   (sconta l'usura dovuta; non amplificabile) e per i record non ancora
   creati `World.newId` consuma un id.
5. Impatto: riservatezza in MP (livello e qualità del carburante di veicoli e
   generatori altrui, presenza di veicoli per id). Nessun danno in SP.
6. Prova: run 2 AUD-1 (§7.1): `status` su un'auto a 35 tile risponde
   `ok total=0 cap=59 grade=empty`, su una pompa a ~25 tile `total=13759`;
   `sample` sulla stessa auto → `no_access`. Kahlua "status answers for a
   vehicle the player cannot reach" (giocatore a 70 tile: `total=20`).
7. Correzione:

   ```diff
   --- a/Contents/mods/TheLastGallon/common/media/lua/shared/TLG/Authority/Handlers.lua
   +++ b/Contents/mods/TheLastGallon/common/media/lua/shared/TLG/Authority/Handlers.lua
   @@ function H.status(player, args)
        local ep, why = ctx.resolve(args.target, ctx)
        if ep == nil then return { ok = false, reason = "unknown_target", detail = why, requestId = args.requestId } end
   +    local ok, reason = ep:canAccess(player)
   +    if not ok then return { ok = false, reason = "no_access", detail = reason, requestId = args.requestId } end
        local rec = Aging.advance(ep:read(), ctx.now, ctx.env)
   ```

   Per rendere `unknown_target` meno parlante, rispondere `no_access` anche
   quando il riferimento non si risolve (una sola ragione per "non per te").

   **Applicata** (2026-11-05, su richiesta del proprietario) con una
   variante: il diff sopra blocca anche chi legge lo stato dal posto di
   guida, perché l'area del tappo è fuori dall'auto. L'harness `fuel` chiede
   proprio così lo stato dell'auto (`carStatus` dopo `FU.enter`). Il
   gestore usa quindi `ep.canObserve` quando l'endpoint lo definisce, e
   `canAccess` altrimenti. Solo l'endpoint del veicolo lo definisce: tappo
   in portata, oppure `player:getVehicle() == vehicle`. `sample` e `treat`
   restano su `canAccess`: dal sedile si legge, non si preleva né si tratta.
   L'hardening su `unknown_target` **non** è applicato: un id inesistente
   risponde ancora `unknown_target`, quindi l'esistenza di un id veicolo
   resta deducibile.
8. Regressione: Kahlua, giocatore lontano `no_access` senza cifre né
   valutazione e senza id consumati; al tappo e dal sedile `ok`; dal sedile
   `sample` resta `no_access`; il sedile di un'altra auto non conta; pompa e
   generatore `no_access` da lontano e `ok` accanto. MP `audit`: i tre stati
   da lontano rifiutati, lo stato della pompa in portata risponde. MP
   `fuel`: `genStatus` (a 1 tile) e `carStatus` (dal sedile) restano verdi.
   Esiti in §7.2.
9. Nessuna dipendenza.

### V-03 — Record mondo trasmesso con `machineSites` e seed

1. V-03; Media su server PvP, bassa su coop; confidenza alta (runtime).
2. `TLG/Integration/World.lua` prima della correzione, righe 84-96 (`transmit`, `requestFromServer`,
   `onReceive`), `Boot.lua:62` (`OnGameStart` → `requestFromServer`),
   `Machines.lua:426-437` (`M.index` scrive `machineSites` nel record mondo).
3. Qualunque client: basta avviare il gioco (il mod chiede il record a ogni
   `OnGameStart`) o chiamare `ModData.request("TLG_World")`.
4. `GlobalModData.receiveRequest` invia la tabella intera; `machineSites` è
   `{ [processId] = { x, y, z } }` di ogni macchina piazzata con lotto in
   corso (fino a 256). Il seed permette di calcolare in anticipo la
   contaminazione di ogni stazione (`WorldInit.stationContamination`) e le
   basi di invecchiamento.
5. Impatto: su PvP la posizione delle basi e delle produzioni altrui, in
   tempo reale; informazione sul mondo (seed, nextId, climateAcc).
6. Prova (run 1): il server ha
   `sites={P152207548-12={x=10665,y=10640,z=0}}`; il client `user` riceve
   via `OnReceiveGlobalModData` la stessa tabella con `machineSites=1` e il
   quadrato del recipiente spawnato → `PASS AUD2_machine_sites_received_by_plain_client`.
   Run 2 AUD-2b: il client ritrasmette una copia forgiata (nextId 999999): il
   server non la applica (§7.1).
7. Correzione: tenere in `TLG_World` solo ciò che serve ai client per le
   anteprime (calendario, `climateLog`, `balanceHistory`, `policy`,
   `installedAt`, `transitionHours`) e spostare `machineSites`, `climateAcc`,
   `seed`, `nextId` in uno store che il server non invia.

   **Errata della prima versione di questo report.** La prima versione
   proponeva una seconda chiave di ModData globale (`TLG_WorldServer`).
   Non funziona: `GlobalModData.receiveRequest` legge la chiave indicata dal
   client (`getUTF`), poi `get(chiave)`, e rimanda la tabella intera a chi
   chiede. Qualunque chiave è leggibile con
   `ModData.request("TLG_WorldServer")`. Anche `GameTime.getModData()` è
   escluso: `GameTime.saveToPacket` lo invia ai client, tranne le chiavi
   `camping`, `farming` e `trapping`.

   **Applicata** (2026-11-05, su richiesta del proprietario) con l'unico
   store nativo trovato che è salvato con la partita e non inviato: la
   modData di un sistema di oggetti globali lato server, senza oggetti
   (`server/TLG/Server/WorldStore.lua`, sistema `tlgworld`). Dal bytecode:
   `SGlobalObjectSystem.save` scrive in `gos_tlgworld.bin` nella cartella
   del salvataggio le sole chiavi di `setModDataKeys` (qui `tlg`).
   `getInitialStateForClient` invia al client solo ciò che restituisce la
   funzione Lua omonima, qui niente. Un comando client verso il sistema
   finisce in un `OnClientCommand` vuoto. Il motore non cancella file `gos_`
   di sistemi non registrati, quindi un mod rimosso e poi riaggiunto ritrova
   lo store.

   Ordine di avvio, dal bytecode: `IsoWorld.init`, e quindi
   `OnInitGlobalModData` e `World.ensure`, viene prima di
   `SGlobalObjects.initSystems`. Vale sul server dedicato (`GameServer.main`)
   e in single player (`GameLoadingState`). Per questo `World.ensure` scrive
   ancora i quattro campi in `TLG_World`, come prima. Il sistema, quando si
   carica, chiama `World.attachServerStore`, che li sposta nello store, li
   toglie dal record pubblico e ritrasmette. Lo stesso percorso migra i
   salvataggi esistenti: vince il valore dello store, `nextId` prende il
   maggiore. Se lo store manca ma il record esiste, nasce un seed nuovo
   perché i nuovi id restino distinti. I lettori usano `World.server()`
   (`newId`, `recordClimate`, `Machines.index/sampleSites/observeFires`,
   il seed di `sample`) o `World.facts()`, che unisce il seed ai campi
   pubblici per `baseline` e `stationContamination`. Se lo store non si
   carica, `World.server()` resta il record pubblico: il mod funziona come
   prima, il server lo scrive nel log e la riservatezza non è garantita.
   Documentato in `docs/migrations.md` e `docs/engine-capabilities.md` (G08).
8. Regressione: Kahlua (spostamento dei campi, id, baseline e acqua della
   stazione uguali con lo stesso seed, somme climatiche nello store, unione
   con un salvataggio vecchio, store perso). MP `audit`: il client riceve
   `TLG_World` senza seed, `nextId`, `climateAcc` né `machineSites`, mentre
   la sonda del server trova il quadrato del recipiente nello store. MP
   `timers`: letture orarie e note dei fuochi dai siti nello store. Esiti in
   §7.2.
9. Nessuna dipendenza dalla build; usa la classe Lua vanilla
   `SGlobalObjectSystem` (`server/Map/SGlobalObjectSystem.lua` di 42.21).

### V-04 — `transfer` generico, istantaneo, senza tubo né corrente

1. V-04; Bassa-media; confidenza alta.
2. `TLG/Authority/Transactions.lua:78-143`, `Resolver.lua:36-97`
   (ogni `kind` è sia sorgente sia destinazione), `Handlers.lua:38-42`.
3. Client modificato; vicinanza richiesta dagli endpoint (2.5 tile; 3.5 tile
   dalla pompa; area del tappo per i veicoli).
4. Il menu offre solo tanica→motore (pour), tanica→pompa, generatore→tanica;
   il gestore accetta qualunque coppia: pompa→tanica, pompa→auto,
   auto→tanica (sifone senza tubo), auto→pompa, generatore→auto, oggetto
   fluido→qualsiasi. Nessuna azione a tempo (vanilla: 50 tick per litro),
   nessun limite di frequenza oltre il ledger (che non limita id diversi).
   La corrente alla pompa è richiesta dal motore solo per inizializzare una
   pompa mai usata (`getPipedFuelAmount`, §3): una stazione già usata resta
   erogabile dal mod a corrente spenta, mentre il menu vanilla la nega.
5. Impatto: integrità del gioco (tempo, tubo, corrente), vantaggio in
   competizione per il carburante; con `generator→item` da 2.5 tile si
   svuota il generatore di un altro giocatore anche attraverso un muro
   (vanilla non ha lo scarico; ma chiunque può spegnerlo o prenderlo).
6. Prova: run 2 AUD-3 (§7.1): da un giocatore `user` accanto alla pompa,
   una richiesta `transfer` ha mosso 5 L nella tanica senza azione né
   animazione (unità `13759 → 13754`); pompa→auto rifiutata lì solo per la
   distanza (4.12 > 3.5 tile). Kahlua "transfer moves pump fuel into a car
   and a can…" (pompa→auto 10 L, poi riempimento del serbatoio con
   `amount=100000`, pompa→tanica 5 L, replay ignorato) e "drains a generator
   and siphons a car…" (generatore svuotato; sifone 20 L in una richiesta dal
   tappo).
7. Correzione: lista bianca delle coppie in `H.transfer` e requisiti
   vanilla:

   ```diff
   --- a/.../TLG/Authority/Handlers.lua
   +++ b/.../TLG/Authority/Handlers.lua
   @@ function H.transfer(player, args)
        local ctx = H.context(player)
        if not protectPours() then args.experimental = true end
   +    local ALLOWED = { ["item>vehicle"] = true, ["item>generator"] = true, ["item>pump"] = true,
   +        ["generator>item"] = true }
   +    local sk, dk = type(args.source) == "table" and args.source.kind, type(args.destination) == "table" and args.destination.kind
   +    if not ALLOWED[tostring(sk) .. ">" .. tostring(dk)] then
   +        return { ok = false, reason = "pair_not_allowed", requestId = args.requestId }
   +    end
        return Tx.transfer(ctx, H.actorKey(player), args)
   ```

   e, in `Resolver` per `kind == "pump"` come destinazione o sorgente,
   `canAccess` che richieda `obj:getSquare():hasGridPower()` o
   `haveElectricity()` con `AllowExteriorGenerator` (le stesse condizioni di
   `ISVehicleMenu.lua:1088`). Per limitare la frequenza: un cooldown per
   attore in `H.context` (es. una mutazione ogni 10 tick) o il passaggio
   obbligato dall'azione a tempo `ISTLGPourFuel`, che oggi è l'unica via del
   menu per i motori.
8. Regressione: Kahlua, le coppie non in lista → `pair_not_allowed`;
   tanica→generatore e generatore→tanica ok; MP `fuel` (pour e drain) verde.
9. Nessuna.

### V-05 — Record del serbatoio svuotato con pompe infinite

1. V-05; Media (disponibilità del carburante di stazione), solo con
   `FuelStationGasInfinite=true`; confidenza media (mock con il wrapper reale
   del mod; runtime NOT RUN, l'autore stesso lo elenca come non provato).
2. `TLG/Integration/Stations.lua:82-90` (`S.read`: con `infinite()` ritorna
   prima della riconciliazione), `:93-101` (`S.write` non tocca le unità),
   `:114-124` (`draw`), `:154-173` (`settle` di `ISTakeFuel`:
   `C.commit(self.petrolCan, "item", merged)` scrive nei fluidi della tanica
   la composizione del record).
3. Nessun attaccante necessario: ogni erogazione vanilla (`draw`) e ogni
   `transfer` dalla pompa riducono il record; la pompa infinita riporta
   sempre 1000 unità, quindi il record parte da ~1000 L e non viene mai
   riallineato.
4. Quando il record arriva a 0: `draw` restituisce una parcella vuota,
   `merged` è la tanica com'era e `C.commit` riporta i fluidi nativi della
   tanica alla composizione precedente: i litri appena erogati da vanilla
   scompaiono. Da quel momento quella pompa non riempie più nessuno.
5. Impatto: su server con pompe infinite, dopo ~1000 L erogati a una pompa,
   negazione del rifornimento per tutti; un giocatore malevolo lo anticipa
   con `transfer` (100 taniche da 10 L). Soggetti: tutti.
6. Prova (Kahlua, `tests/audit/test_audit.lua`): con l'opzione attiva, 80
   trasferimenti portano il record a 0 mentre `getPipedFuelAmount` resta
   500 e lo stato è `infinite`; poi, con `ISTakeFuel` mock avvolto dal vero
   `S.install()`, 5 L di Petrol aggiunti dall'azione vengono azzerati da
   `complete()`. Da verificare in gioco: server con
   `FuelStationGasInfinite=true`, erogare >1000 L a una pompa, poi una
   tanica (atteso dal codice: la tanica torna vuota).
7. Correzione: con la pompa infinita il record è illimitato: in `draw` e in
   `Tx.transfer` (via `ep:read`) ricaricare il record prima di prelevare.

   ```diff
   --- a/.../TLG/Integration/Stations.lua
   +++ b/.../TLG/Integration/Stations.lua
   @@ function S.read(obj, persist)
   -    if infinite() then return rec, "infinite" end
   +    if infinite() then
   +        -- The pump never runs dry: keep the record at its capacity, the
   +        -- composition and condition as they are (untracked inflow at the
   +        -- baseline, as a refilled reservoir).
   +        local short = rec.cap - Supply.total(rec)
   +        if short > 1e-6 then
   +            local base, at = C.inflowAt()
   +            rec = TLG.Authority.Transactions.reconcile(rec, { total = rec.cap }, base, "gasoline", at)
   +            rec.frac = 0
   +        end
   +        return rec, "infinite"
   +    end
   ```

8. Regressione: il test Kahlua "a vanilla pump->can dispense on a drained
   reservoir record loses the delivered petrol" deve dare 5 L nella tanica;
   "with FuelStationGasInfinite the reservoir record is drained…" deve
   trovare il record a capacità dopo ogni lettura; i casi `fuel` (pompa
   finita) invariati.
9. Dipende dall'opzione sandbox vanilla.

### V-06 — Nessun limite all'intervallo simulato

1. V-06; Bassa; confidenza alta.
2. `TLG/Domain/Climate.lua:283-315` (`segments`: un segmento per giorno),
   `Fuel/Aging.lua:84` e `Production/Process.lua:260` (chiamano `segments`
   su `[rec.t, now]`), nessun controllo di `t` in `Migrations`.
3. Serve V-01 (modData forgiato con `t` molto negativo) o un salvataggio
   manipolato. Un giocatore onesto non lo provoca: `t` nasce da
   `getWorldAgeHours()` e dalle basi (`start - preAge`, ≤ 75 giorni).
4. Ogni lettura del record (ogni comando, ogni wrapper, ogni lettura oraria
   per le macchine) costruisce `(now - t)/24` tabelle: t = -1e6 h → 41 667
   segmenti (misurato: la lettura resta nell'ordine del decimo di secondo);
   t = -1e9 h → 4·10⁷ segmenti e tabelle → blocco del thread di gioco o
   `OutOfMemory` del server per quella lettura; per le macchine si ripete
   ogni ora (`sampleSites`) finché il record esiste.
5. Impatto: disponibilità del server (una lettura sola blocca il tick);
   richiede però la capacità B.
6. Prova: Kahlua "a sidecar dated 1e6 hours ago builds over 40000 climate
   segments on one read" (passa: >40 000 segmenti, nessun limite).
7. Correzione: in `Aging.advance` e `Process.advance` (o in `segments`)
   limitare l'intervallo e coalescere i giorni fuori dal log climatico:

   ```lua
   Climate.MAX_SPAN_HOURS = 24 * 365 * 20   -- oltre, il passato è un solo segmento stagionale
   function Climate:segments(t0, t1, thermal, site)
       if t1 - t0 > Climate.MAX_SPAN_HOURS then t0 = t1 - Climate.MAX_SPAN_HOURS end
       ...
   ```

   insieme alla validazione di V-07 (`t` finito e non oltre `now`).
8. Regressione: lo stesso test con attesa `#segs <= 7300`; i test di
   equivalenza "un avanzamento grande = molti piccoli" devono restare validi
   entro lo span massimo.
9. Nessuna.

### V-07 — Record persistenti creduti senza validazione dei campi

1. V-07; Bassa; confidenza alta.
2. `Migrations.lua:63-69` (`sidecar`), `Containers.lua:112-117`,
   `Stations.lua:77-82`, `Generators.lua:69-77`, `Vehicles.lua:91-96`
   (campi copiati senza `Supply.check`), `Machines.lua:104-113`.
3. Come V-06.
4. `q` con valori negativi → `Supply.normalize` solleva "negative
   component" a ogni lettura → ogni comando sull'oggetto risponde
   `server_error`, ogni wrapper logga un errore (log spam); `deg`/`stab`/`mic`
   NaN → valutazioni NaN (`startFactor` NaN: il confronto fallisce e il
   cancello di avviamento lascia passare); `cap` 0 → divisioni per zero in
   `Supply.fraction` sono protette, ma `Supply.free` negativo blocca ogni
   ingresso.
5. Impatto: oggetto inutilizzabile e rumore nei log; con V-01 un giocatore
   può rendere "incommandabile" la pompa di una stazione per tutti (ogni
   `S.read` fallisce finché il modData non è pulito).
6. Prova: statica (il test Kahlua "malformed references…" copre gli input di
   rete, non i record; da aggiungere).
7. Correzione: in `Migrations.sidecar` (o in un `Supply.sanitize`) applicare
   `Supply.check(rec)` dopo la ricostruzione; se fallisce, ignorare il
   sidecar (stato "invalid_schema" già previsto → `C.read` restituisce nil,
   `H.*` rispondono `invalid_schema`) oppure ricostruire la base
   (`World.baseline`) e loggare una volta per id.
8. Regressione: Kahlua con sidecar `q={gasoline=-1}`, `deg={gasoline=0/0}`,
   `t=1/0`, `cap=0`: la lettura non solleva e il record risulta ignorato o
   ricostruito; i record validi invariati.
9. Nessuna.

### V-08 — `experimental` deciso dal client

1. V-08; Bassa (hardening); confidenza alta.
2. `Transactions.lua:114-119`, `Handlers.lua:33-42`, `ISTLGPourFuel.lua:54`.
3. Client modificato.
4. La conferma del giocatore è trasmessa come `experimental=true` nella
   richiesta; il server la crede. L'opzione sandbox `ProtectIncompatiblePours`
   può solo forzare `true` quando è spenta, non impedire quando è accesa:
   un client modificato versa comunque miscele incompatibili (nel proprio
   motore o in quello altrui, con le stesse conseguenze di V-04).
5. Impatto: aggira una conferma, non un divieto; griefing: versare acqua o
   etanolo nel serbatoio di un altro (vanilla permette solo Petrol nei
   serbatoi; il mod, qualunque fluido del registro).
6. Prova: lettura del codice (la pour con `experimental=true` passa la
   verifica di compatibilità: `test_transactions.lua` lo copre come
   comportamento voluto).
7. Correzione: distinguere "conferma" (UI) da "permesso": una terza
   posizione dell'opzione ("vietato") che faccia ignorare `experimental`;
   e per i motori altrui, solo il proprietario/chi è nel veicolo (V-09).
8. Regressione: con l'opzione "vietato", pour incompatibile →
   `incompatible` anche con `experimental=true`.
9. Nessuna.

### V-09 — Nessuna proprietà né safehouse; salvataggio al richiedente

1. V-09; Media in MP; confidenza alta (statica).
2. `ConversionHandlers.lua:62-91` (`run`: `takeItems(player, r.consumed)`,
   `giveItems(player, r.returned)`), `:119-125` (`cancel`, `remove`);
   `Conversions/Project.lua:798-838` (cancel/remove verificano solo abilità,
   ricette e attrezzi del richiedente; `startedBy` e `workers` non sono
   usati); `MachineHandlers.lua:151-180` (`loadWash` prende il wash dal
   fermentatore di chiunque entro 2 tile), `:271-311` (`abort`, `collect`
   su qualunque macchina entro 2.5 tile).
3. Giocatore senza privilegi, con le abilità/attrezzi richiesti (per il
   generatore: Mechanics 2, Electricity 2, ricetta "Generator", chiave
   inglese e cacciavite), entro 2.5 tile (generatore) o 4 tile (veicolo):
   la portata non attraversa porte o muri in modo esplicito, è una distanza.
4. Un lavoro avviato da A, con parti consegnate da A, può essere annullato
   da B: `Project.cancel` calcola `returned` (75 % delle parti delle fasi
   iniziate, 100 % delle altre) e il gestore le mette nell'inventario di B.
   `remove` su una conversione commissionata: 50 % delle parti a B. Lo
   stesso per `machine.collect` (etanolo altrui nella propria tanica) e
   `loadWash` (wash altrui nel proprio alambicco). Le safehouse del gioco non
   sono consultate (`SafeHouse`), quindi anche dentro una safehouse di cui
   B non è membro.
5. Impatto: furto di parti e prodotto; sabotaggio di lavori (cancel) e
   produzioni (abort); vanilla permette di prendere le macchine da terra
   (fuori dalle safehouse), non di cancellare un lavoro altrui.
6. Prova: statica; da coprire con un test Kahlua (attore B che cancella il
   progetto di A e riceve `returned`) e un caso MP a due client.
7. Correzione (ConversionHandlers): limitare `cancel`/`remove` a chi ha
   avviato il lavoro o vi ha lavorato, e restituire le parti sul quadrato
   del dispositivo:

   ```diff
   --- a/.../TLG/Authority/ConversionHandlers.lua
   +++ b/.../TLG/Authority/ConversionHandlers.lua
   @@ local function run(player, args, fn)
        local actor = CD.actor(player, project, args.conversion)
   +    if project and (args.command == "conversion.cancel" or args.command == "conversion.remove") then
   +        local mine = project.startedBy == actor.id or (project.credit and (project.credit[actor.id] or 0) > 0)
   +        if not mine then return fail("not_yours", { rev = project.rev }) end
   +    end
   ```

   (passando `args.command` dal dispatcher, o con due `run` distinti) e per
   le macchine: registrare `owner = actorKey` in `machineLoadFerment`/
   `loadDry`/`loadWash` e richiederlo in `collect`/`abort`/`loadWash` oppure,
   più semplice e coerente con il gioco, rifiutare ogni comando su oggetti
   in una safehouse di cui il richiedente non è membro:

   ```lua
   local function safehouseAllows(player, square)
       local sh = SafeHouse and square and SafeHouse.getSafeHouse(square)   -- API da verificare su 42.21
       if sh == nil then return true end
       return sh:playerAllowed(player)
   end
   ```

   (nome dei metodi da confermare con `javap zombie.iso.areas.SafeHouse`).
8. Regressione: Kahlua: B non può cancellare il progetto di A
   (`not_yours`); A sì, con le parti restituite; MP `conversion` verde.
9. Dipende dalle API `SafeHouse` della build per la variante safehouse.

### V-10 — Harness di sviluppo: comandi server senza privilegio

1. V-10; Bassa; confidenza alta.
2. `tests/ingame/TheLastGallonHarness/.../server/TLGHarness/MPServer.lua`
   (`services.give`, `hold`, `spawn`, `setup_*` con `setPerkLevelDebug`,
   `addVehicleDebug`, `IsoGenerator.new`; `Events.OnClientCommand` sul
   modulo `TLGH` senza verifica del ruolo).
3. Qualunque giocatore, solo se il mod `TheLastGallonHarness` è caricato
   dal server.
4. Il pacchetto non lo include: `tools/package.ps1` copia solo
   `Contents/mods/TheLastGallon/{42,common}` e rifiuta percorsi `TLGHarness`;
   `dist/TheLastGallon-0.1.0.zip` non contiene file dell'harness
   (verificato sull'albero `dist/`).
5. Impatto: nullo per i giocatori del pacchetto; totale (item, livelli,
   veicoli) se un operatore installasse per errore la cartella `tests/ingame`.
6. Prova: ispezione del pacchetto e del launcher.
7. Correzione (hardening): in `MPServer.lua` rifiutare i servizi se
   `player:getAccessLevel() ~= "Admin"` a meno di un file marcatore nella
   cache del server (`TLG_harness_dev.txt`), e aggiungere a `mod.info`
   dell'harness una descrizione "never on a public server" (già c'è).
8. Regressione: nessuna necessaria.
9. Nessuna.

### 7.1 Risultati del run 2 dell'harness (`-Only audit -NonAdmin`, rete attiva)

Evidenze: `docs/evidence/2026-11-05_audit_mp_run2_client_a.txt`, `_server.txt`,
`_launcher.txt`. Client `tlga`, ruolo `user` (`setaccesslevel user`), mondo
nuovo, `ElecShutModifier=14` (rete attiva: `hasGridPower=true` sul quadrato
della pompa, letto sul server e sul client). Esito: `SUMMARY pass=12 fail=0`.

| Verifica | Osservato sul server | Esito |
| --- | --- | --- |
| AUD-1 `status` veicolo a 35 tile (`dist=35.0`) | `ok=true total=0 cap=59 sealed=false rev=0 grade=empty` | V-02 confermata |
| AUD-1 `sample` stesso veicolo | `ok=false reason=no_access detail=not_at_fuel_cap` | il controllo esiste, `status` lo salta |
| AUD-1 `status` pompa e generatore a ~25 tile | pompa `total=13759 primary=gasoline`; generatore `total=0 grade=empty` | V-02 confermata |
| AUD-1 `status` id veicolo inesistente | `unknown_target detail=no_vehicle` | enumerazione per differenza di risposta |
| AUD-2 `ModData.request("TLG_World")` | il client riceve `seed=153062351 nextId=16 machineSites={P…-15={x=10665,y=10640,z=0}}`, uguale alla sonda del server | V-03 confermata |
| AUD-2b il client ritrasmette una copia con `nextId=999999` | il server riporta `nextId=16` invariato | ipotesi smentita (nessuna vulnerabilità) |
| AUD-3 `transfer` pompa→tanica da 1 tile, nessuna azione a tempo | `ok=true moved=5`; unità della pompa `13759 → 13754`; sul server il record della pompa (`R…-16`, rev 1, con acqua 14.32 L e sedimento 6.96 L) e quello della tanica (`S…-17`, 5 L, provenienza `k=in from=R…-16`) | V-04 confermata (istantaneo; la corrente era attiva) |
| AUD-3 `transfer` pompa→auto dal tappo (`inArea=true`, pompa a 4.12 tile) | `no_access_source detail=out_of_reach` | la coppia è accettata dal codice (test Kahlua) ma qui la geometria del sito supera i 3.5 tile |
| AUD-4 `syncItemFields()` con `deg.gasoline=7.7777`, `stab=1.5` sulla tanica | `probe_item`: `sidecar={audit=forged,…,deg={gasoline=7.7777},…,stab=1.5000,…} fluid=5.0000` | V-01 confermata (item) |
| AUD-4 `transmitModData()` sulla pompa con acqua e sedimento rimossi, `deg=0` | `pumpSide={audit=forged,…,deg={gasoline=0.0000},…,q={gasoline=13732.7199},…}` (prima: `water=14.3248, sediment=6.9553, deg 0.2579`) | V-01 confermata (oggetto del mondo) |
| AUD-4 `transmitModData()` sul generatore con `tlgConv` Commissioned forgiato | `probe_generator`: `profile=generator_si_flex` | V-01 confermata (conversione gratis) |

Il run 1 (`…_run1_*.txt`, con `ElecShutModifier=0`) ha dato gli stessi esiti
per AUD-2 e AUD-4 item; la stazione non aveva pompe inizializzate (vedi §3,
`getPipedFuelAmount`), quindi AUD-1/3 e AUD-4 pompa/generatore sono stati
ripetuti nel run 2.

### 7.2 Correzioni applicate (V-02, V-03) e verifica

Applicate dopo la consegna, su richiesta del proprietario. File del
pacchetto toccati:

| File | Modifica |
| --- | --- |
| `shared/TLG/Authority/Handlers.lua` | `H.status` chiama `ep.canObserve` (o `canAccess`) prima di leggere: `no_access` senza cifre; il seed di `sample` viene da `World.server()` |
| `shared/TLG/Integration/Vehicles.lua` | `ep:canObserve`: al tappo, o seduto in quell'auto |
| `shared/TLG/Integration/World.lua` | `World.SERVER_FIELDS`, `World.server()`, `World.attachServerStore()` (spostamento e migrazione), `World.facts()`; `ensure`, `recordClimate`, `newId`, `baseline` usano lo store |
| `shared/TLG/Integration/Machines.lua` | `machineSites` letto e scritto in `World.server()` (`index`, `sampleSites`, `observeFires`) |
| `shared/TLG/Integration/Stations.lua` | contaminazione delle stazioni seminata da `World.facts()` |
| `server/TLG/Server/WorldStore.lua` (nuovo) | sistema di oggetti globali `tlgworld` senza oggetti; chiave salvata `tlg`; nulla ai client; comandi client ignorati; avviso nel log se lo store manca su un server |

Documenti aggiornati: `docs/migrations.md` (record mondo e store del
server), `docs/engine-capabilities.md` (G08: ModData globale e `GameTime`
non privati, sistemi di oggetti globali privati, ordine di avvio).

**Kahlua** (`tools\run-tests.ps1 -Entry tests/audit/run_audit.lua`):
`audit cases=13 passed=13 failed=0 assertions=101`. I due casi `status`
ora attendono il rifiuto da lontano e la risposta in portata; il caso nuovo
"V-03 fixed" copre lo spostamento dei campi, id, baseline e acqua della
stazione identici con lo stesso seed, somme climatiche nello store, unione
con un salvataggio vecchio e store perso. Suite di dominio:
`modules=26 cases=218 passed=218 failed=0`. Compilazione:
`compiled=124 errors=0`.

**Run 3 dell'harness** (`-Clients 1 -Only audit -NonAdmin`, mondo nuovo,
client `tlga` con ruolo `user`): `SUMMARY pass=14 fail=0`. Evidenze:
`docs/evidence/2026-11-05_audit_mp_run3_fixes_{client_a,server,launcher}.txt`.

| Verifica | Osservato | Esito |
| --- | --- | --- |
| `status` auto a 42 tile, pompa a ~34, generatore a ~31 | tutti `ok=false reason=no_access`, nessun `total` | V-02 corretta |
| `status` pompa dopo esserle andato accanto | `ok=true total=8068 primary=gasoline` | uso legittimo intatto |
| `status` id veicolo inesistente | `unknown_target detail=no_vehicle` | invariato (hardening non applicato) |
| sonda del server dopo lo spawn di un fermentatore in lavorazione | store `seed=155582228 nextId=13 sites={P155582228-12={x=10665,y=10640,z=0}}`; nel record pubblico `seed`, `nextId`, `machineSites` assenti | i campi sono nello store |
| `ModData.request("TLG_World")` dal client | ricevuto (`event=true policy=new_world`), `seed=nil nextId=nil climateAcc` assente, `machineSites=0` | V-03 corretta |
| il client ritrasmette `TLG_World` con `nextId=999999` | lo store del server resta `nextId=13` | invariato |
| log del server | `world fuel history created … seed=155582228` alle 14:13:23.804, poi `world record: seed,nextId moved to the server store` alle 14:13:28.365 | ordine di avvio come dal bytecode |
| file nel salvataggio del server | `Saves/Multiplayer/TLGDev/gos_tlgworld.bin` (155 byte) accanto a quelli vanilla | lo store è persistito |
| AUD-3, AUD-4 (V-04, V-01) | stessi esiti del run 2 | non toccati da queste correzioni |

**Run 4** (`-Clients 1 -Only fuel`, regressione funzionale): `SUMMARY
pass=18 fail=2`. Evidenze:
`docs/evidence/2026-11-05_audit_mp_run4_fuel_{client_a,server,launcher}.txt`.

* `generator_status` a 1 tile dal generatore: `ok=true total=7.988`, e
  `generator_burn_followed` passa.
* `car_status` dal posto di guida: `ok=true total=29`. Il sedile dà
  accesso alla lettura, come voluto.
* Falliscono `car_starts_on_station_fuel` e, di conseguenza,
  `car_idle_burn_followed`: il motore non si avvia. Il serbatoio ha il
  0.27 % d'acqua, oltre lo 0.2 % tollerato dal motore stock, e il gate di
  avviamento del mod lo rifiuta. L'acqua viene dalla pompa: con il seed di
  questo mondo (155583546) `stationContamination` dà a quel quadrato
  0.2657 % d'acqua, una delle stazioni "cattive" (circa una su dieci per
  progetto, docs/balance.md). Calcolata a parte nella VM Kahlua, la stessa
  pompa con il seed del run 3 ha lo 0.0223 %. Il seed è casuale a ogni
  mondo nuovo e la formula non è cambiata: la correzione ha spostato il
  seed, non il suo uso. È un'instabilità del caso `fuel` (mondo nuovo, seed
  casuale), non una regressione.

**Run 6** (`-Clients 1 -Only fuel` ripetuto, mondo e seed nuovi): `SUMMARY
pass=20 fail=0`. Il motore parte; `car_status` dal posto di guida risponde
`total=48.9736` e `car_idle_burn_followed` passa (serbatoio 48.9980 →
48.9736 L, uguale al record letto dallo stato); `generator_status`
`total=7.985`. Evidenze:
`docs/evidence/2026-11-05_audit_mp_run6_fuel_{client_a,server,launcher}.txt`.

**Run 5** (`-Clients 1 -Only timers`, letture orarie e note dei fuochi dai
siti nello store): `SUMMARY pass=6 fail=0`. Con 32 macchine accanto a un
falò: 96 letture orarie su 96 corrispondenti all'aria, 576 note dei fuochi
su 576; lo stato chiesto a una macchina accanto al fuoco e a una lontana
dal fuoco risponde `ok`. Evidenze:
`docs/evidence/2026-11-05_audit_mp_run5_timers_{client_a,server,launcher}.txt`.

**Single player, salvataggio e ripresa** (`tools\run-sp-harness.ps1 -Mode
fireplace-reload -TimeoutMinutes 60`, lo stesso caso del run 25 del
progetto): fase 1 `SUMMARY pass=8 fail=0`, fase 2 `SUMMARY pass=20
fail=0`, come nel run 25. Un fermentatore accanto a un camino, salvato a
metà lotto, uscita al menu e ripresa. Dopo la ripresa
`RTFB.hourly_list_survives` trova la sua voce nella lista oraria, letta
ora dallo store: `{x=10679,y=10297,z=0}`. Letture, note, lotto e fuoco sono
come lasciati, poi il lotto prosegue. Nel log del client:
`world fuel history created … seed=1441565760`, poi `seed,nextId moved to
the server store`. Dopo la ripresa non c'è nessun avviso di seed nuovo, e
quindi lo store si è ricaricato con il suo seed. Il file
`gos_tlgworld.bin` (270 byte) è nella cartella del salvataggio. Evidenza:
`docs/evidence/2026-11-05_audit_sp_fire_reload.txt`.

**Non verificato in gioco.** Un riavvio del server dedicato con lo store:
il file è scritto alla chiusura (run 3) e il caricamento passa per lo stesso
`SGlobalObjectSystem.load` della ripresa in single player, ma il caso
`-Restart` non è stato rieseguito. Un salvataggio creato con la versione
precedente del mod e caricato con questa: il percorso del codice è lo
stesso di un mondo nuovo (i campi sono in `TLG_World` quando lo store si
aggancia), e l'unione è coperta da Kahlua. Un host cooperativo: il server
è un processo separato, come il dedicato.

## 8. Ipotesi non confermate, hardening, bug funzionali

**Ipotesi smentite durante l'audit.**

* Un client che trasmette `TLG_World` (`ModData.transmit`) non sovrascrive il
  record del server: il motore scatena solo l'evento e il gestore del mod
  scrive solo sui client (bytecode; run 2 AUD-2b).
* `args` non tabellare in `OnClientCommand`: impossibile dal trasporto
  (firma Java); comunque `Net.lua` avvolge il dispatcher in `pcall` e
  risponde `server_error` (Kahlua: `H.dispatch(p, "treat", 5)` solleva,
  `"x"` risponde `unknown_operation`).
* Riferimenti con `inf`/NaN/indici fuori range, importi negativi/NaN/stringa,
  requestId lunghi o non stringa, `op` sconosciuti, conversioni inesistenti:
  tutti rifiutati senza sollevare (test Kahlua "malformed references…" e
  "unknown conversion id").
* Replay: il ledger per attore risponde dalla memoria allo stesso id; dopo
  64 richieste successive l'id vecchio esegue di nuovo (test Kahlua), ma
  l'attore è lo stesso che potrebbe inviare una richiesta nuova: nessuna
  escalation.
* Trasferimento da pompa senza corrente: per una pompa mai usata il motore
  non espone unità senza corrente (run 1: "no pump with stock" con
  `ElecShutModifier=0`); resta vero per le pompe già inizializzate (bytecode
  di `getPipedFuelAmount`), come descritto in V-04.
* Quantità e crafting: le ricette (`TLG_machines.txt`) consumano input
  vanilla verificati; i converter del dominio sono conservativi (test del
  repository); `Process.collect` non emette più di quanto prodotto;
  `machine.collect` è limitato dallo spazio libero della tanica.
* `experimental`, `expectedRevision`, `sugarKg`, `waterL`, `kg` del client:
  tutti clampati sul server ai massimi delle ricette e alle disponibilità
  reali dell'inventario (`tonumber` di stringhe strane dà inf/nil → massimo).
* `sendServerCommand` con tabelle contenenti funzioni o oggetti Java: il
  motore li salta (`PZNetKahluaTableImpl.canSave`); nessuna risposta del mod
  li contiene.
* Server malevolo: nessuna superficie oltre il testo mostrato; i callback
  client sono in `pcall`.
* Memoria: ledger limitato a 64 per attore (gli attori sono gli username);
  `tlgKnowledge` cresce di una voce per record campionato per giocatore;
  `machineSites` ≤256; log climatico ≤450 giorni; letture macchina ≤480.
  Le `Reservations` non sono mai create (codice morto innocuo).

**Hardening ulteriore.**

* Aperto dopo la correzione di V-02: `H.status` e tutti i gestori: rispondere con un'unica ragione per "non
  disponibile per te" (`no_access`) invece di `unknown_target`/`no_vehicle`
  (enumerazione).
* `Net.pending` sul client cresce se il server non risponde (una voce per
  richiesta): aggiungere una scadenza.
* `machineLoadWash` consegna lo starter con `AddItem` senza
  `sendAddItemToContainer` (il client lo vede solo dopo una risincronizzazione:
  da verificare in MP; in `takeOnServer` e nell'harness il mod usa già
  `sendAddItemToContainer`).
* Loggare sul server, con rate limit, le richieste rifiutate per
  `no_access`/`pair_not_allowed` per attore: oggi un client che enumera non
  lascia traccia.
* `tlgKnowledge` nel modData del giocatore: in MP il server lo scrive ma il
  client lo legge dal proprio modData (`FuelContextMenu.lua:63`); il
  trasporto è implicito (l'harness verifica la risposta, non la voce
  "What I know"): da verificare.
* Pacchetto: `workshop.txt` con `visibility=private` e manifesto SHA-256
  sono buone pratiche già presenti; aggiungere al rilascio un controllo che
  `dist/` non contenga `.devcache` o credenziali (oggi vero).

**Bug funzionali senza impatto di sicurezza dimostrato.**

* V-05 è anche un bug funzionale per i server a pompe infinite.
* `S.read` con una pompa già inizializzata ma senza corrente: se il motore
  riportasse -1 (uninitialized senza corrente è il caso coperto), il record
  verrebbe riconciliato a 0 litri: da verificare con una stazione usata e poi
  senza corrente (NOT RUN).

## 9. Copertura dell'audit

**Esaminato per intero (lettura riga per riga).** `Core`, `Boot`, `Client/Net`,
`Server/Net`, `Server/Loot`, `Authority/*` (Handlers, MachineHandlers,
ConversionHandlers, Transactions, Resolver, Reservations, Ledger),
`Integration/*` (World, Containers, Native, Stations, Vehicles, Generators,
Machines, ConversionDevices, Manual), `Actions/*`, `UI/*` client e
`UI/Format`, `Persistence/Migrations`, `Util/*`, `Domain/WorldInit`,
`Domain/Climate`, `Domain/Balance`, `Domain/Fuel/*`, `Domain/Consumers`,
`Domain/EngineEffects`, `Domain/Production/Process`,
`Domain/Conversions/Project`, `Content/Fuels|Storage|Consumers|Production|
Feedstocks|Containers|Conversions`, `Registry`; gli script
`TLG_items/machines/fluids/models.txt`, `sandbox-options.txt`; `mod.info`;
`tools/package.ps1`, `run-tests.ps1`, `run-mp-harness.ps1`, `setup-devenv.ps1`
(parti); l'harness `MPServer.lua`, `MPHarness.lua` (struttura),
`MPHarnessCases.lua` (caso fuel), `Steps.lua`, `MPShared.lua`, `Report.lua`.

**Esaminato per sola ricerca di API di gioco ed eventi (moduli di dominio non
raggiungibili da rete né da persistenza in 0.1.0).** `Domain/Gas`,
`Domain/Energy/*`, `Domain/Routes`, `Domain/Automation`, `Domain/FuelService`,
`Content/Biodiesel|Biogas|WoodGas|Propane|Energy`: nessuna chiamata di gioco,
nessun adapter; esclusi dall'analisi delle vulnerabilità.

**Non esaminato.** Gli asset binari (`.fbx`, `.x`, `.png`) e i file
`AnimSets/*.xml` (solo verificato che `package.ps1` li validi come XML);
`tools/blender/*.py` e gli script di generazione icone (non distribuiti, non
eseguiti dal gioco); `SPHarness.lua`, `ServerExperiments.lua`, `LuaProbe.lua`,
`Driver.lua` dell'harness (solo sviluppo).

**Verifiche non eseguibili o non eseguite.** V-05 in gioco (server con pompe
infinite); V-09 con due client (furto delle parti); una stazione usata e poi
senza corrente; il comportamento dell'anti-cheat del motore sui pacchetti
`ObjectModData`/`SyncItemFields` con `AntiCheat` configurato a livelli
diversi dal default del server di test (il server TLGDev usa le impostazioni
predefinite di `-adminusername`/`-nosteam`); una rete reale (tutto su una
macchina, come per il resto del progetto).

## 10. Allegati e riesecuzione

* Test Kahlua: `tools\run-tests.ps1 -Entry tests/audit/run_audit.lua`
  (12 casi e 63 asserzioni alla consegna; 13 casi e 101 asserzioni dopo le
  correzioni di V-02 e V-03; `tests/audit/mocks.lua` definisce i mock del
  gioco, `tests/audit/test_audit.lua` i casi).
* Harness MP: `tools\run-mp-harness.ps1 -Clients 1 -Only audit -NonAdmin`
  (circa 4 minuti; caso in `TLGHarness/AuditCases.lua`; sonde `probe_square`
  e `probe_world` in `MPServer.lua`); risultati in
  `docs/evidence/2026-11-05_audit_mp_run{1,2}_{client_a,server,launcher}.txt`
  (run 1: 3 pass / 5 non eseguibili per la stazione non inizializzata senza
  corrente; run 2: 12 pass / 0 fail). Dopo le correzioni (§7.2):
  `…_run3_fixes_*` (`audit`, 14/0), `…_run4_fuel_*` (`fuel`, 18/2 per una
  stazione "cattiva" del seed casuale), `…_run5_timers_*` (`timers`, 6/0),
  `…_run6_fuel_*` (`fuel` ripetuto, 20/0); single player
  `2026-11-05_audit_sp_fire_reload.txt` (8/0 e 20/0).
* Modifiche per le correzioni di V-02 e V-03 (§7.2): sei file del pacchetto
  runtime; nell'harness, `TLGH.worldRecord()` in `Steps.lua` e le letture di
  `SPHarness.lua` e `MPServer.lua` spostate sullo store (`machineSites`,
  seed, `nextId`, `climateAcc`).
* Modifiche ai file di test e di sviluppo fatte per questo audit (nessuna
  al pacchetto runtime): `tests/audit/{mocks,test_audit,run_audit}.lua`
  (nuovi), `TLGHarness/AuditCases.lua` (nuovo), `MPServer.lua` (due sonde
  in coda), `tools/run-mp-harness.ps1` (`audit` in `-Only` e una nota).
* Bytecode: `"C:\Program Files\Amazon Corretto\jdk17.0.11_9\bin\javap.exe"
  -c -p -cp projectzomboid.jar <classe>` dalla cartella del gioco.
