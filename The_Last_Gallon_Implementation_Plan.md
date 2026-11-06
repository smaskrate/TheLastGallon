# The Last Gallon
## Complete implementation analysis and code-agent handoff

**Version:** 1.0 — 30 October 2026  
**Game:** Project Zomboid, one pinned Build 42 patch  
**Status:** implementation specification; no mod implementation or in-game compatibility has been validated  
**Scope:** the full fuel deterioration, production, conversion and energy-infrastructure mod discussed in this conversation

This document restores the complete implementation brief in a standalone form. It is intended to be supplied directly to a coding agent alongside access to the development repository and the installed game.

## Contents

1. Product goal and full scope
2. Development environment and required deliverables
3. Engine verification gates
4. Architecture and repository structure
5. Canonical data model
6. Conservation and numerical rules
7. Deterioration, storage and world initialization
8. Stations, transfers and native accounting
9. Shared production framework
10. Complete alternative-energy pathways
11. Persistent workshop conversions
12. Electricity and heat networks
13. Automation
14. Multiplayer authority
15. Persistence, migrations and unloaded simulation
16. Player interfaces and localization
17. Milestone backlog and ticket format
18. Acceptance tests and performance
19. Vanilla asset audit
20. Asset-by-asset requirements
21. Art delivery specifications
22. Content budgets, audio and licensing
23. Compatibility and release packaging
24. Ready-to-use coding-agent prompt
25. Release definition of done and principal risks
26. References and evidence classification

---

## 1. Product goal and full scope

Build a survival overhaul in which the player initially lives on the energy left behind by the old world and eventually establishes a supply they can maintain.

The gameplay progression is:

1. Scavenge fuel and discover that supplies have different conditions.
2. Sample reserves and distinguish chemical deterioration from contamination.
3. Preserve good supplies and appropriately treat recoverable ones.
4. Recover equipment and establish alternative production.
5. Convert compatible generators and vehicles.
6. Automate routine processing and protect emergency reserves.
7. Operate a dependable installation and restore distribution sites.

The endpoint is a reliable system earned through preparation and investment. Successful infrastructure should reduce repetitive labor. It should not trigger arbitrary disasters simply because the player has become self-sufficient.

### Target and supported modes

- One exact Project Zomboid Build 42 patch, recorded in the repository.
- Single-player.
- Hosted multiplayer.
- Dedicated-server multiplayer.
- New worlds.
- Existing saves through a documented migration policy.
- Late-start scenarios.
- English source strings and Italian localization.
- A declared initial set of supported chassis, devices and maps.

Do not advertise generic “B42 compatibility” until the exact tested patches are identified. The installed game, source scripts and asset catalogs remain authoritative.

### Full feature scope

| System | Required full-release behavior |
| --- | --- |
| Fuel identity | Distinct fuel compositions, quantity, deterioration and contamination |
| Deterioration | Storage-, fuel- and time-dependent aging |
| Inspection | Sampling, estimated/confirmed condition, compatibility and useful diagnostics |
| Treatment | Preservation, eligible contamination removal and compatible blending |
| Storage | Portable containers, supported vehicle/generator tanks and station reservoirs |
| Gas stations | Original reserves deteriorate; infrastructure can be repaired and reused |
| Ethanol | Complete renewable chain and compatible engine conversions |
| Biodiesel | Oil/fat processing, diesel consumers and seasonal behavior |
| Wood gas | Stationary and vehicle-mounted gasifiers |
| Propane | Scavenging, appropriate storage, transfers and conversions |
| Biogas | Digestion, gas storage and stationary heat/electricity production |
| Electricity | Generation, battery storage, charging, losses and prioritized loads |
| Vehicles | Persistent, tested conversion projects for selected chassis |
| Automation | Batch queues, connections, protected reserves and automatic control |
| Multiplayer | Server-controlled mutations, validation and synchronization |
| Persistence | Save/load, unloaded simulation, migration and recovery |
| Presentation | Functional UI, appropriate assets, audio, manuals and localization |
| Distribution | Reproducible package, clean installation and documented support |

The first playable release is an intermediate milestone. The full scope includes all routes above.

Aircraft fuel support is a possible later adapter. Helicopter flight is a separate project and is not a dependency of this mod.

### Game-balance principles

- Fuel deteriorates unevenly; there is no universal midnight expiration event.
- Storage and preservation buy meaningful time.
- Unknown condition is different from known bad condition.
- Players receive readable symptoms before severe problems.
- Renewable pathways have distinct advantages, rather than one universal best fuel.
- At least one sustainable route is attainable without unique rare loot.
- Mature production becomes less labor-intensive.
- Every essential consumed input must have a replenishable route before a pathway is described as sustainable.
- New characters can learn to operate inherited infrastructure.
- A stable installation is allowed to remain stable.

A default campaign profile can gradually introduce problems across several in-game months, with faster and slower presets. These timings are game design values, not claims about exact real-world fuel shelf life.

## 2. Development environment and required deliverables

The agent needs a legally installed copy of the target game, an actual development checkout and isolated test saves.

Before gameplay implementation:

1. Read repository instructions and inspect existing work.
2. Locate the installed game and development mod directory.
3. Record the exact client and server version, branch and relevant source hashes.
4. Inspect shipped Lua and script definitions.
5. Select a matching API annotation revision if helpful.
6. Establish the actual supported Lua language/runtime subset.
7. Configure source control, linting, domain tests and packaging.
8. Create a reproducible single-player test world.
9. Bring up local hosting and a dedicated server with two clients where available.

Do not test migrations against the user's only world copy.

### Required documentation

| File | Purpose |
| --- | --- |
| docs/environment.md | Versions, paths, tools, development installation and server setup |
| docs/engine-capabilities.md | Verified integration points, experiments, results and limitations |
| docs/decisions.md | Architecture decisions and reasons |
| docs/asset-audit.csv | Actual asset inventory, missing assets, provenance and validation |
| docs/support-matrix.md | Tested vehicles, generators, maps and external mods |
| docs/test-results.md | Exact tests run, results and tests not run |
| docs/balance.md | Tunable coefficients, gameplay targets and campaign results |
| docs/migrations.md | Persistent versions and installation/removal policies |
| docs/player-guide.md | Gameplay instructions and troubleshooting |
| docs/release-checklist.md | Packaging, compatibility and publication readiness |

Umbrella is useful for discovery and editor tooling, but annotations do not establish runtime behavior. Pin its revision alongside the game version.

If game execution is unavailable, the agent may implement and test domain modules. Runtime checks must remain marked NOT RUN; an untested adapter is not release-ready.

### Work process

For each ticket:

- Define the player-visible outcome and acceptance criteria.
- Identify dependencies, files and integration points.
- Implement a small complete change.
- Add meaningful tests for the behavior.
- Run relevant domain and in-game checks.
- Record evidence and unresolved limitations.
- Update migrations and documentation.
- Produce a reviewable commit.

Parallel workers can own independent modules after shared contracts exist. Keep schemas, registries and global integration ownership centralized. Parallelization is an execution option, not a prerequisite.

## 3. Engine verification gates

The first priority is proving that quantity and fuel properties stay synchronized through native operations.

The inspected Umbrella annotations include fluid transfer operations, a numeric generator fuel interface, and multiple lifecycle methods on vehicle refueling actions. They support investigating separate adapters; they do not prove that one universal hook exists. See references R1–R4.

| Gate | Question | Required experiment |
| --- | --- | --- |
| G01 Packaging | What structure loads in this patch? | Minimal mod, script item and callback; clean launch |
| G02 Fluids | How do type, mixtures and metadata transfer? | Fill, pour, split, merge, empty, drop and reload |
| G03 Vehicle consumption | Where does driving/idling change quantity? | Instrument a known route, idle period, refuel and siphon |
| G04 Generator consumption | How can fuel and burn behavior be extended? | Start/stop/refill/consume/save without double subtraction |
| G05 Generator lifecycle | Does state survive pickup? | Pick up, carry, replace and reconnect a modified generator |
| G06 Stations | Is fuel per-pump, shared or special-cased? | Compare pumps, reservoirs and sandbox modes |
| G07 Action authority | Which action stage mutates on the server? | Inspect installed bodies and test cancellation/retry |
| G08 Persistence | Which state stores and IDs are reliable? | Save/load, chunk unload, restart and reconnect |
| G09 Per-instance vehicles | Can one vehicle be modified independently? | Convert one of two identical vehicles and compare |
| G10 Electricity | Which consumers can be controlled independently? | Two-load supply and priority experiment |
| G11 Vehicle visuals | How are extra parts or model variants represented? | Import one mount and test orientations, doors and passengers |
| G12 Unloaded machines | What already simulates outside loaded chunks? | Leave a machine, vary resources/weather, return after days |
| G13 Assets | Which relevant props and sounds actually exist? | Catalog, spawn and interact with candidates |
| G14 Compatibility | What can bypass the adapters? | Inspect/run selected vehicle, generator and fuel mods |

### First mandatory end-to-end proof

**Station → container → vehicle → container → generator**

Check quantity, composition, condition and contamination at every step. Repeat with partial transfers, save/load, inventory movement, generator pickup and multiplayer reconnect.

### Handling a failed gate

Document the minimal reproduction and consequences. Prototype a supported alternative, such as a mod-owned generator or chassis-specific model variant. Update the scope decision.

Do not silently replace an advertised mechanic with an inaccurate implementation. A Java patch is not the automatic answer to an unavailable Lua hook.

## 4. Architecture and repository structure

### Layers

| Layer | Responsibility |
| --- | --- |
| Domain | Pure fuel, aging, blending, treatment, processing and energy calculations |
| Authority | Validation, reservations, commits, deduplication and reconciliation |
| Adapters | Native containers, vehicles, generators, stations, appliances and world objects |
| Persistence/scheduling | State storage, clocks, migrations and catch-up |
| Presentation | UI, tooltips, models, sounds, animations and localization |
| Content registries | Fuels, storage, recipes, machines, consumers, conversions and assets |

The domain must be testable without launching Project Zomboid.

### Logical module layout

~~~text
TLG/Domain/Fuel
TLG/Domain/Storage
TLG/Domain/Production
TLG/Domain/Consumers
TLG/Domain/Conversions
TLG/Domain/Energy
TLG/Authority/Commands
TLG/Authority/Transactions
TLG/Authority/Reconciliation
TLG/Integration/Containers
TLG/Integration/Vehicles
TLG/Integration/Generators
TLG/Integration/Stations
TLG/Integration/Electricity
TLG/Persistence
TLG/Simulation
TLG/Registry
TLG/UI
TLG/Presentation
~~~

These are proposed project paths, not existing game API names. Place them into the verified client/server/shared and versioned distribution folders.

Keep source art, tests and packaging tools outside the runtime package.

### Internal contracts

The following names describe interfaces to implement:

~~~lua
FuelService.advance(batch, timeInterval, environmentSegments)
FuelService.previewTransfer(source, destination, amount)
FuelService.previewBlend(inputs, consumerProfile)
ProductionService.plan(recipeId, inputs, machineState)
ProductionService.advance(process, resources, interval)
ConsumerService.evaluate(profileId, supply, operatingState)
EnergyService.dispatch(network, interval, producerState, demand)
ConversionService.canBegin(project, actor, vehicle)
MigrationService.upgrade(savedState, targetSchema)
~~~

Calculation functions return proposed changes and diagnostics. The authority layer commits mutations. UI previews use the same calculation rules as authoritative operations.

### Registries

Define stable, validated registries for:

- FuelDefinition.
- StorageProfile.
- ConsumerProfile.
- RecipeDefinition.
- MachineDefinition.
- ConversionDefinition.
- SiteDefinition.
- AssetDefinition.

Check for duplicate IDs, undefined references, invalid capacities, negative yields and impossible recipes before running a development build.

## 5. Canonical data model

### Liquid supply

~~~text
schemaVersion
stableSupplyId
revision
capacity
componentQuantities
chemicalCondition
contamination
storageProfile
storageCondition
preservationTreatment
lastSimulatedGameTime
batchLabel
boundedProvenance
~~~

Use explicit documented units. Store enough per-component or grouped state to prevent deterioration-reset exploits.

### Inspection knowledge

~~~text
sampledAt
inspectionPrecision
observedCondition
observedContamination
sampledSupplyRevision
~~~

Inspection is separate from physical state. An expert may obtain better information; the underlying fuel does not change according to who inspects it.

### Resource types

| Resource | Canonical quantity |
| --- | --- |
| Liquid fuel | Documented liquid volume |
| Solid feedstock | Mass |
| Gas | Documented normalized quantity plus storage profile |
| Battery | Usable stored energy |
| Producer/consumer capacity | Power |
| Process heat | Thermal energy |

Do not represent propane, biogas, solid fuel and electricity as interchangeable liquid liters.

### Bounded representation

Do not retain every historical pour indefinitely. Use bounded composition and deterioration summaries, with limited provenance for display.

A volume-weighted summary may suit compatible homogeneous liquids. Water separation and incompatible mixtures need explicit handling. Averaging timestamps and calling the result a new fuel age is insufficient.

## 6. Conservation and numerical rules

Mandatory invariants:

1. Quantities are finite, nonnegative and within capacity.
2. Component quantities match the declared total under the chosen measurement convention.
3. Transfers conserve contents except explicitly modeled losses.
4. Splitting and recombining preserves properties.
5. New containers, labels and crafting wrappers never rejuvenate fuel.
6. Both participants are advanced to the same time before a transfer.
7. Filtering removes only the eligible contamination.
8. Removed contaminants and any lost carrier fuel are accounted for.
9. Stabilizer changes future rates and has a bounded effective concentration.
10. A small fresh addition cannot reset a large degraded reserve.
11. Compatibility is separate from condition and nominal energy.
12. Production consumes inputs and produces each output only once.
13. Battery round trips lose usable energy.
14. Electrical and recovered thermal outputs share the same input budget.
15. Waste processing cannot recover the original input energy repeatedly.
16. Unknown IDs and malformed requests are rejected.
17. Repeated tiny operations cannot manufacture quantity through rounding.

Preserve fractional remainders where required. Define numerical tolerances and test them.

Fuel condition should not automatically mean an equal percentage reduction in chemical energy. Consumer suitability, starting behavior, effective output and wear are separate game-level effects.

## 7. Deterioration, storage and world initialization

### Aging inputs

- Fuel type/composition.
- Storage profile and container condition.
- Seal condition.
- Preservation treatment.
- Relevant environment.
- Elapsed world game time.

Accumulate exposure, then map it to suitability. Keep the exposure rate separate from the consumer penalty curve so campaign speed can be tuned coherently.

Player grades: good, weathered, poor, unsuitable for the selected engine. Add modest UI hysteresis to prevent labels flickering near a boundary.

### New worlds

- Create one deterministic seed and fuel-history epoch.
- Seed station variation by stable site identity.
- Initialize portable supplies using the start scenario.
- Persist initialization.
- Do not generate fresh supplies merely because a town is first explored late.

### Existing saves

Provide these policies:

1. Begin deterioration at installation.
2. Initialize from current world age.
3. Apply a configurable transition period.

Persist the policy and epoch once. Reconnecting/reinstalling must not repeatedly grant fresh reserves.

### Storage interactions

Implement sampling, preserving, appropriate filtering, eligible water separation, blending, cleaning empty storage, sealing and repairing infrastructure.

Distinguish chemical deterioration from contamination. Filtering must not reverse oxidation or universally repair phase-separated blends.

Normal interactions should protect communal reserves from accidental incompatible mixing. Deliberate experimentation must be a clearly separate action.

### Unloaded supplies

Advance when accessed or consumed. Use recorded environmental segments or a documented coarse profile. Do not apply the current temperature to the entire past.

A large time advance and many smaller advances must agree within the specified tolerance.

## 8. Stations, transfers and native accounting

Every adapter declares:

- Quantity owner.
- Consumption owner.
- Supported transfer and lifecycle operations.
- Metadata storage.
- Replication method.
- Reconciliation policy.

A native tank may own volume while a sidecar owns composition and deterioration, but only if every supported operation can be reconciled.

**There must be only one consumption owner per adapter.** Native and mod burn must never both subtract the same operation.

### Stations

- Verify pump-to-reservoir relationships.
- Support separate reservoir types where applicable.
- Separate capacity, contents, tank condition and dispensing state.
- Preserve properties during extraction and refilling.
- Repair infrastructure without restoring quantity or quality.
- Bound transfers by source, capacity and rate.
- Support appropriate powered and, where implemented, manual extraction.
- Give custom maps an authored reservoir-mapping mechanism.
- Document behavior with infinite-fuel sandbox settings.

A station with exhausted original reserves can become a player-run storage, blending and distribution point.

### Reconciliation

Unknown changes to native quantity must not automatically create fresh fuel. Detect them, log useful diagnostics, and apply an explicit adapter policy.

Publish a support matrix for transfer paths. Third-party actions that bypass metadata propagation cannot be declared compatible without testing.

## 9. Shared production framework

### Machine state

~~~text
Ready
InputsReserved
Processing
Paused
OutputReady
Faulted
Maintenance
Decommissioned
~~~

Specify all transitions. Track where each input and intermediate product resides.

### Recipe schema

| Field | Required meaning |
| --- | --- |
| Eligible inputs | Feedstock types/categories |
| Batch bounds | Minimum/maximum amount |
| Stages | Preparation, waiting, processing, finishing |
| Energy | Heat, electricity, mechanical work |
| Duration | Per-stage elapsed time |
| Consumables | Filters and abstract processing supplies |
| Output | Quantity, composition, quality and byproducts |
| Interruptions | Pause, partial loss or recoverable state |
| Skills | Time, consistency and efficiency modifiers |
| Storage | Compatible output and available capacity |
| Automation | Queue and reserve constraints |

Active processes retain their recipe revision or an immutable parameter snapshot. A balance update must not reinterpret half-processed inputs.

Output capacity should be checked before committing completion. A full destination pauses or stores a bounded output; it cannot repeatedly emit the same finished batch.

Keep chemistry abstract and game-facing. Real-world manufacturing procedures are not required.

## 10. Complete alternative-energy pathways

### Ethanol

Implement preparation, fermentation, processing, testing, compatible storage and blending.

The product remains ethanol or a declared blend, not renamed gasoline.

Provide a supported converted spark-engine generator and vehicle. At least one complete chain must operate without continually adding scavenged gasoline.

Account for crop/food competition, water, processing heat, throughput and quality. Starter and essential processing inputs need replenishable routes.

### Biodiesel and diesel equipment

Implement eligible oils/fats, processing supplies, batch quality, compatible consumers and cold-weather behavior.

Introduce explicit diesel profiles. Do not silently reclassify all original vehicles as diesel.

Finite processing inputs must remain visible in the supply-chain model. A renewable feedstock alone does not make the whole chain sustainable.

Support seasonal preparation with readable effects and appropriately supported equipment.

### Wood gas

Implement prepared/dried solid feedstock, hopper loading, warm-up, operating output, gas handling, filter loading and service.

Stationary and vehicle gasifiers share domain logic. The gasifier consumes solid feedstock to produce an operating gas stream; it does not generate liquid “wood gasoline.”

Vehicle versions impose tested cargo/weight/performance costs. An optional separate conventional reserve uses explicit storage and switching rules.

Bulk loading and service actions avoid one-stick-at-a-time chores.

### Propane

Implement finite scavenged supplies, appropriate cylinder/bulk profiles, compatible transfers and converted consumers.

Storage vessel condition is separate from fuel longevity. Generic liquid pouring cannot handle propane.

Propane serves as a transitional supply and emergency reserve rather than a falsely renewable fuel.

### Biogas

Implement eligible waste/manure inputs, digestion time, temperature effects, gas handling, bounded storage, compatible stationary consumers and optional useful heat recovery.

Track startup delay and cold operation. Give byproducts conservative residual value. Reprocessing loops and respawning inputs must not create accidental unlimited high-yield energy.

### Electricity

Implement generation, batteries, losses, charge/discharge limits, demand, priorities and supported vehicle charging.

A battery stores energy. Charging from a fueled generator preserves the upstream fuel requirement.

### Bootstrap requirement for every route

Publish:

- Knowledge and skills.
- Required equipment.
- Initial external energy.
- Renewable inputs.
- Finite dependencies.
- Recovery after power loss.
- Late-world acquisition.

At least one early pathway must be startable with attainable manual preparation and independent heat. An installation cannot require its own unavailable finished fuel as the only startup option.

## 11. Persistent workshop conversions

### Conversion definition

~~~text
supportedChassis
originalEngineProfile
targetConsumerProfile
requiredKnowledge
requiredTools
requiredModules
workStages
cargoAndWeightImpact
fuelStorageChanges
visualConfiguration
reversalAndSalvageRules
~~~

Stages: inspect, prepare/drain/isolate, install, configure, test, commission.

Reserve a specific device and track work persistently. Benefits apply only when their installation stage is complete.

### Required lifecycle cases

- Interrupted installation.
- Lost tool or component.
- Vehicle moved during work.
- Concurrent workers.
- Engine replacement after conversion.
- Removal/salvage.
- Destruction.
- Save/load in the middle of work.

### Chassis support

Start with one verified vehicle. Expand to one small car, one pickup/utility vehicle and one van/heavier hauler.

Actual IDs must come from the installed game. Not every chassis must support every route. Publish the tested conversion matrix.

A bi-fuel conversion has separate supplies and switching behavior. An electric conversion includes motor/controller/battery and must reconcile starting, charging, sound, status, repair and movement.

A cosmetic battery meter over unchanged gasoline behavior is not completion.

## 12. Electricity and heat networks

Components:

- Producers.
- Storage.
- Registered consumers.
- Explicit connection topology.
- Dispatch controller.
- Reserve and auto-start policies.

For each interval:

1. Determine source availability.
2. Determine demand.
3. Allocate by priority and stable tie-breaking IDs.
4. Apply power limits.
5. Account for storage and conversion losses.
6. Record unmet demand/curtailment.
7. Advance fuel and stored energy.

Use hysteresis and minimum operating periods to prevent on/off oscillation.

Support a native appliance only where the ability to control it has been verified. Start with mod-owned equipment where necessary. Do not show a priority setting that cannot affect the actual consumer.

Generation models:

- Solar: time, weather, exposure and equipment condition.
- Wind: bounded weather-derived production.
- Hydro: authored or verified appropriate flow locations.
- Fueled generation: shared consumer accounting.

Network loops cannot count a source twice. Rebuild affected topology, not every network every frame.

Heat recovery remains inside the input energy budget. It cannot be allocated in full to several processes simultaneously.

## 13. Automation

Required features:

- Batch queues.
- Input/output connections.
- Target reserves.
- Protected food/feedstock quantities.
- Output-full pause.
- Low-resource notifications.
- Automatic generator start/stop.
- Bulk loading/unloading.
- Conditional operation where feasible.

Example rule: maintain transport reserve up to a target while preserving a minimum food stock.

Queues must not reserve unlimited materials or repeatedly consume inputs after reconnect.

A paused machine shows a concrete reason: missing input, power, heat, output capacity, maintenance or incompatible storage.

Mature infrastructure should reduce repetitive management. Size and hardware determine the service interval; do not enforce constant arbitrary failures.

## 14. Multiplayer authority

Clients request operations; the server validates and commits them.

### Example request

~~~text
requestId
sourceId
destinationId
requestedAmount
expectedSourceRevision
expectedDestinationRevision
~~~

### Server procedure

1. Validate actor, references, proximity and access.
2. Advance participants to a common authoritative game time.
3. Check revisions.
4. Check compatibility.
5. Bound quantity.
6. Calculate all deltas.
7. Commit the operation.
8. Increment revisions.
9. Return authoritative results.

Use bounded request deduplication. Retry must not repeat the operation.

Do not trust client-reported quality, output amount, elapsed time or production completion.

A sequential game event loop may not need database-style locks, but it still needs serialized, consistent mutations.

### Required scenarios

- Simultaneous withdrawals.
- Disconnect/cancel during an action.
- Partial progress and retry.
- Moving/removing an item.
- Picking up a processing machine.
- Joining during a conversion.
- Stale UI state.
- Spoofed quantity and inaccessible object requests.

Crash consistency depends on actual native save behavior. Test split native/metadata persistence and recovery rather than assuming atomic disk commits.

## 15. Persistence, migrations and unloaded simulation

Version separately:

- Persistent schema.
- Recipes.
- Consumer/adapter definitions.
- Balance profiles.
- Assets/content.

Migrations are deterministic, repeatable and tested with fixtures.

When settings change, advance state under the old configuration before applying new rates. Otherwise a changed coefficient may rewrite historical deterioration.

For unloaded processing, simulate meaningful events:

- Resource exhaustion.
- Batch completion.
- Output full.
- Battery depleted.
- Relevant environment or supply change.

Do not replay every frame. Bound catch-up work and schedule it without losing elapsed time.

Retain enough history for weather-sensitive calculations, or document an appropriate deterministic approximation.

Module removal needs a defined process for active batches and installed conversions. Preserve unknown future schemas and prevent unsupported mutations.

Never “migrate” all custom fuel into fresh gasoline.

## 16. Player interfaces and localization

| View | Required information |
| --- | --- |
| Inspection | Type, estimated/confirmed condition, contamination, sample age |
| Storage | Capacity, contents, condition, treatment |
| Production | Inputs, stage, energy, output, pause reason |
| Blending | Allowed components, compatibility, predictions, saved recipes |
| Conversion | Supported project, requirements, progress and resulting capabilities |
| Energy | Generation, demand, storage, priorities and runtime estimates |
| Station | Reservoirs, pump condition, accepted supplies and access |
| Admin/debug | State, revisions, adapter, timestamps and reconciliation diagnostics |

Unknown condition must not look like known bad condition.

Use text and symbols as well as color. Important functions must not rely on tiny world-model labels.

Use the same domain calculation for UI previews and server results. Explain gameplay consequences rather than internal exception names.

Introduce localization keys with each feature. English is the source language; include Italian in the initial supported set.

Manuals should explain startup, compatibility and troubleshooting inside the game. Essential knowledge has multiple acquisition paths, and inherited equipment should offer an attainable way to learn operation.

## 17. Milestone backlog and ticket format

| Milestone | Work | Exit gate |
| --- | --- | --- |
| M0 Discovery | Pin build, inspect APIs/assets, capability experiments, tooling | Evidence-backed architecture and known blockers |
| M1 Domain | Units, registries, state, aging, blending, treatment, serialization | Conservation/time tests pass |
| M2 Integration | Containers, vehicles, generators, pumps, IDs, authority, synchronization | Transfer chain works in SP/MP |
| M3 First survival loop | Decay, inspection, preservation, ethanol, one generator/vehicle conversion | Attainable renewable operation in fresh/late worlds |
| M4 Reliability | Migrations, unloaded simulation, recovery, profiling | Reload/reconnect/catch-up gates pass |
| M5 Workshop | Better equipment, queues, blending, reserves, restored stations | Multi-day unattended installation |
| M6 Diesel | Diesel equipment, biodiesel, seasonal support, chassis expansion | Complete tested supply chain |
| M7 Wood gas/propane | Gasifiers, warm-up, service, solid feedstock, cylinders and conversions | Distinct stationary/vehicle routes work |
| M8 Biogas | Digestion, temperature, gas storage, consumers, heat | Farm installation passes balance tests |
| M9 Electricity | Batteries, dispatch, priorities, charging, generation, supported EV | Working networks without duplication |
| M10 Content | Art, sound, translations, supported chassis/maps/integrations | Support matrix matches tested package |
| M11 Release | Balance campaigns, upgrades, documentation, packaging and media | All release gates pass |

Do not release deterioration without the complete initial alternative supply loop.

### Ticket template

~~~text
Ticket ID:
Player-visible outcome:
Dependencies:
Owned files/modules:
Verified integration points:
Implementation tasks:
Acceptance criteria:
Required tests:
Migration impact:
Asset dependencies:
Documentation updates:
Completion evidence:
~~~

### Suggested initial tickets

- M0-01: reproduce minimal mod loading.
- M0-02: inspect fluids and complete a metadata transfer experiment.
- M0-03: instrument vehicle and generator consumption.
- M0-04: verify action authority in two-client multiplayer.
- M0-05: verify pump reservoir identity.
- M0-06: test pickup/persistence and custom power control.
- M0-07: inventory assets and import a representative placeholder.
- M1-01: implement units, registry validation and state codecs.
- M1-02: implement transfers, mixing and treatment with invariants.
- M1-03: implement time advancement and initialization.
- M2-01: integrate portable containers.
- M2-02: integrate vehicle fuel and consumption.
- M2-03: integrate generator fuel and lifecycle.
- M2-04: integrate station supplies and dispensing.
- M2-05: complete authoritative transfer requests and replication.
- M3-01: implement the shared production state machine.
- M3-02: implement the ethanol production chain.
- M3-03: implement generator and vehicle conversion projects.
- M3-04: implement inspection/production/conversion UI.
- M3-05: validate fresh-world and late-world bootstrap.

Expand later milestones into the same ticket format after earlier engine gates resolve. Do not estimate all remaining work from guessed engine capabilities.

## 18. Acceptance tests and performance

| Area | Required cases |
| --- | --- |
| Quantity | Full/empty, partial, overflow, repeated tiny transfers |
| Properties | Split/recombine, mixed condition, treatment and preservation |
| Exploits | New-container reset, relabeling, crafting wrappers, request replay |
| Consumers | Driving, idling, generators, native/custom accounting |
| Production | Power loss, cancellation, full output, repeated completion, recipe update |
| Time | Large/small step equivalence, fast-forward, unloaded state, regression |
| Persistence | Save each state, reload conversions, old-schema migration |
| Multiplayer | Concurrent actions, reconnect, stale state, spoofed requests |
| Electricity | Losses, power limits, source exhaustion, priorities, graph loops |
| Vehicles | Engine replacement, interruptions, destruction, variants |
| Stations | Multiple pumps, refilling, mixed types, sandbox modes |
| Progression | Fresh/no-grid, six-month, one-year, inherited installation |
| Compatibility | Vanilla, each supported integration, supported combinations |
| Assets | Scale, placement, access, pickup, save/load and MP rendering |

Add randomized state-machine tests over sequences of transfer, mixing, aging, processing, interruption and save/load.

### Performance acceptance

Record a reference machine, world and baseline. Measure the added cost for:

- Many dormant supplies.
- Clusters of active machines.
- Multiple electrical networks.
- Large catch-up intervals.
- Several clients using shared storage.

Dormant records must not cause a full-map scan each frame. Rebuild only affected networks and cache stable adapter lookups where appropriate.

Set numeric performance budgets from the measured baseline, not unsupported FPS promises.

### Progression checks

Every supported scenario must reach basic working power without a unique unrepeatable loot item. Bootstrap supplies initialize once per world/location, not per new character or login.

A working installation survives character death and remains learnable by a successor.

## 19. Vanilla asset audit

The first playable version should target **zero bespoke 3D models**. Fuel composition, condition and batch identity are mainly data and UI.

The author of Industrial Distillery & Biofuel System describes using vanilla presses, barrels, stills, industrial tanks and distillery equipment (R6). Treat these as reuse candidates, not proof that every required placeable or animated asset exists in the target build.

A visual prop is not automatically a portable inventory item or functional workstation.

### Availability classes

- verified_vanilla_reference
- vanilla_candidate_unverified
- external_dependency_reference
- original_required
- optional_polish

### Required audit columns

~~~text
projectAssetId
purpose
targetBuild
availabilityClass
verifiedRuntimeReference
sourcePath
evidence
reuseMethod
customWorkRequired
footprint
variants
sourceAuthor
licenseOrPermission
milestone
placeholder
validationStatus
~~~

Runtime references remain empty until verified.

## 20. Asset-by-asset requirements

These IDs are commissioning/tracking IDs, not game script IDs.

| ID | Asset | Reuse candidates to inspect | Likely original work |
| --- | --- | --- | --- |
| A01 | Sampling/testing kit | Bottles, tools, examination animation | Icon; optional small world prop |
| A02 | Fuel identification | Containers, fonts and UI widgets | Symbols, labels and condition pictograms |
| A03 | Ethanol workstation | Still/distillery/workshop props | Assembly only if stock assets are unsuitable |
| A04 | Fermentation vessel | Barrels/vats | Optional lid/airlock and state details |
| A05 | Oil press | Existing presses | Conditional custom assembly |
| A06 | Biodiesel skid | Tanks, drums, industrial pieces | Distinct processor if stock arrangement is insufficient |
| A07 | Transfer/blending station | Pumps, drums, tanks | Hoses/pump assembly and status details |
| A08 | Stationary wood-gas rig | Some barrels and piping | Likely custom gasifier/cooler/filter assembly |
| A09 | Vehicle wood-gas module | Supported vehicle geometry | Likely custom mounted unit and chassis fitting |
| A10 | Biogas digester | Agricultural/industrial tanks | Conditional custom assembly |
| A11 | Low-pressure gas holder | No appropriate stock asset verified | Likely custom gas holder |
| A12 | Battery bank | Batteries and shelving | Likely rack and connection assembly |
| A13 | Controller/inverter | Electrical cabinets | Faceplate, indicators, optional cabinet |
| A14 | Charging point | Electrical/industrial props | Likely connector and post assembly |
| A15 | Propane conversion | Propane containers | Vehicle cradle, mounts and details |
| A16 | EV conversion | Existing vehicle shell | Battery enclosure/mounts; optional motor |
| A17 | Solar installation | Vanilla/dependency audit | Panel/frame if original generation assets are needed |
| A18 | Wind installation | Dependency audit | Turbine/mast/rotor if implementing original content |
| A19 | Hydro installation | Waterwheel/industrial audit | Wheel/turbine/generator as needed |
| A20 | Restored station | Existing pumps/tanks/building | Product labels, signage and status |

Most likely new art: wood-gas machinery, gas holder, conversion mounts, battery/charging assemblies and project icons.

Conditional art: still, press, fermentation vessels, industrial tanks, biodiesel processor and renewable-generation structures.

Not baseline requirements: a new map, human models, new cars from scratch, helicopter assets, or separate can geometry for every blend.

## 21. Art delivery specifications

Import one representative machine and one vehicle module before authoring the full set.

Confirm:

- Runtime format.
- Coordinate orientation and scale.
- Texture conventions.
- Footprint and interaction side.
- Collision and placement.
- Attachment/rotation support.
- Animation support.
- Shadows/transparency.
- Save/load.
- Multiplayer rendering.

Each original asset must include:

- Editable sources.
- Runtime exports.
- Texture sources.
- Origin/scale documentation.
- Required operating/fault presentation.
- Provenance and redistribution rights.
- In-game validation evidence.

Vehicle mounts require chassis-specific checks for doors, seating, cargo access, model variants, damage and shadows.

If generic attachments are unsuitable, use a tested model variant or another supported representation. Functional prototypes may show the conversion in the vehicle panel while the final visual method is being validated.

A technically loadable model is not sufficient: it must be readable, usable and consistent with placement and collision.

## 22. Content budgets, audio and licensing

These are planning ranges, not engine limits or a purchasing list.

| Category | First playable | Full polished package |
| --- | ---: | ---: |
| New world models | Target 0; possibly 1 | Approximately 6–10 after audit |
| Vehicle module families | Functional placeholders acceptable | Approximately 3–5 plus chassis variants |
| Icons/status symbols | 8–12 | 25–40 |
| Reusable UI views | About 3 | About 6–8 |
| New sound files | Target 0 | About 12–20 if stock sounds are insufficient |
| New particle effects | 0 | Usually 0–3 |
| Localization keys | About 100–180 | About 300–600 |
| Release art | None for private testing | Thumbnail, banner and screenshots |

### Audio

Audit existing operation, transfer, repair, fire/smoke and UI sounds first.

Potential original families:
- Processing loop.
- Press/processor loop.
- Gasifier loop.
- Gas-system operating cue.
- Startup/shutdown transitions.
- A few recognizable maintenance/fault cues.

Sound playback and zombie-attracting world noise are separate controls. Audio mastering must not accidentally change simulated attraction radius.

Prefer existing appropriate smoke/steam effects. Complex explosions and custom fluid shaders are not core requirements.

### Rights and provenance

Reference installed vanilla assets where supported rather than copying game assets into the package.

Workshop inspiration or a declared dependency is not permission to redistribute another author's models or sounds. Record permissions/licenses for external content.

The coding agent can implement UI, registry-driven labels, import tooling, localization scaffolding and placeholders. Release-quality machinery and vehicle mounts still require visual review.

## 23. Compatibility and release packaging

Prefer narrow adapters to broad replacements.

For each integration, record:
- Tested version.
- Feature ownership.
- Quantity/consumption ownership.
- Required load order, if any.
- Supported configurations.
- Known conflicts.
- Upgrade/removal behavior.

Do not attempt broad external compatibility before the vanilla baseline works.

### Package contents

- Verified metadata and versioned mod layout.
- Runtime Lua/scripts.
- Required original assets.
- Localization.
- Sandbox settings.
- User manual.
- Changelog.
- Support matrix.
- Required third-party notices.

Exclude tests, source art, development saves, temporary logs and unrelated game files.

### Player documentation

Explain:
- Why fuel behaves differently.
- Sampling and uncertainty.
- Compatible fuels and conversions.
- First sustainable supply chain.
- Paused-machine diagnosis.
- Existing-save installation.
- Module disabling/removal requirements.

### Release gates

Rehearse clean installation and upgrade from the previous supported version. Test the final packaged artifact rather than only the development folder.

Workshop publication is a separate action after package review. A planning task or local implementation request does not automatically authorize publication.

## 24. Ready-to-use coding-agent prompt

Supply this document with the prompt below.

~~~text
Implement “The Last Gallon,” a Project Zomboid fuel deterioration,
alternative-fuel, conversion and energy-infrastructure mod using the
attached implementation analysis as the product specification.

Work through milestones M0–M11. Complete and validate dependency gates
before expanding downstream systems.

FIRST:
1. Read repository instructions and inspect existing work.
2. Locate and record the exact installed game/server version.
3. Establish an isolated development mod and test saves.
4. Inspect shipped Lua/scripts and matching API annotations.
5. Create the environment, capability, decision, asset-audit,
   support-matrix, test-results, balance and migration documents.
6. Run the mandatory integration and asset experiments from M0.

Do not invent game APIs, script IDs, asset references, persistence
guarantees or multiplayer behavior. Record source evidence and runtime
experiments for game-facing integration points.

Use pure testable domain modules with separate adapters. Every adapter
must explicitly choose its quantity owner and consumption owner.
Never subtract the same native consumption twice.

The first integration proof is:
station → container → vehicle → container → generator.

Preserve quantity, composition, chemical condition and contamination
through transfers, saves, reconnects and pickup/placement.

Make multiplayer authority part of the initial architecture. Clients
request actions; the server validates and commits results. Handle
duplicates, stale revisions, cancellation and concurrent use.

Implement conservation rules and randomized/state-machine tests.
Use world game time. Require loaded and unloaded processing to agree
within documented tolerances.

The first playable milestone must contain deterioration AND a complete
attainable renewable supply chain, one compatible generator and one
compatible vehicle. Do not release decay without a progression route.

Complete the staged full scope: ethanol, diesel/biodiesel, wood gas,
propane, biogas, battery storage, generation/dispatch, supported vehicle
conversions, automation, restored stations, migrations, localization,
content and packaging.

Audit installed assets before commissioning models. Prefer verified
vanilla references in prototypes. Track missing assets and provenance.
Do not copy third-party assets without appropriate permission.

Version persistent schemas, active recipe parameters and adapter
definitions. Preserve partial processes and interrupted conversions.

If a required capability is unavailable, create a minimal reproduction,
document the limitation and prototype a supported alternative.
Do not silently replace an advertised feature with a misleading
approximation.

FOR EACH TICKET:
- State the intended behavior and dependencies.
- Implement the smallest complete change.
- Run relevant automated/runtime tests.
- Record exact results and tests not run.
- Update documentation, migrations and compatibility evidence.
- Produce a reviewable commit.

Use parallel workers for independent modules only after shared contracts
are agreed and when the execution environment/instructions permit it.
Keep schema and integration ownership centralized.

Do not claim runtime tests passed when the game or multiplayer setup
was unavailable. Prepare a release package, report outstanding gates,
and do not publish the Workshop release automatically.
~~~

## 25. Release definition of done and principal risks

The full release is complete only when:

- Every advertised pathway has a playable tested loop.
- Every supported transfer path preserves fuel state.
- Native and mod quantities remain reconciled.
- All production and energy invariants pass.
- Multiplayer and dedicated-server tests pass.
- Save/load, pickup/placement and unloaded simulation pass.
- Existing and late-world bootstrap scenarios pass.
- Supported chassis and map combinations are documented.
- Required assets are verified and licensed appropriately.
- English/Italian text and player documentation are complete.
- Performance is measured against the declared baseline.
- Clean installation and upgrade pass using the packaged artifact.
- No core behavior is represented only by a placeholder.
- Remaining optional integrations are clearly distinguished from shipped scope.

| Risk | Early detection | Response |
| --- | --- | --- |
| Native transfer bypasses metadata | Instrumented end-to-end chain | Narrow supported adapter boundary; explicit compatibility |
| Double fuel consumption | Measured drive/idle/generator runs | One consumption owner |
| Generator pickup loses state | Pickup/save/reload test | Stable lifecycle mapping |
| Vehicle changes affect all instances | Two identical vehicles test | Per-instance method or dedicated supported variant |
| Power UI cannot control appliances | Two-load isolation spike | Registered controllable consumers |
| Fuel resets through mixing/time | Randomized state tests | Canonical bounded state and consistent timestamps |
| Unloaded production duplicates output | Output-full and catch-up tests | Event-based completion with persisted process state |
| Renewable route depends on finite input | Supply-chain audit | Replenishable route or honest transitional classification |
| Art commissioned unnecessarily | Installed asset inventory | Reuse first; commission confirmed gaps |
| Large-world performance degrades | Recorded workload benchmark | Lazy updates, local topology rebuilds and bounded queues |
| Scope grows beyond working baseline | Milestone gates | Complete vertical slices before expansion |
| Unsupported update breaks saves | Version pinning and migration fixtures | Explicit supported-version policy |

The first concrete deliverable is the M0 evidence report plus the working transfer prototype. Subsequent work follows the milestone gates.

## 26. References and evidence classification

These references informed the analysis. They do not replace local verification of the selected game build.

- **R1 — Umbrella repository:** https://github.com/PZ-Umbrella/Umbrella
- **R2 — FluidContainer annotations, pinned revision:** https://github.com/PZ-Umbrella/Umbrella/blob/13d01f9ee58fa48773553920db56d06f0005e7f8/library/java/zombie/entity/components/fluids/FluidContainer.lua
- **R3 — IsoGenerator annotations, pinned revision:** https://github.com/PZ-Umbrella/Umbrella/blob/13d01f9ee58fa48773553920db56d06f0005e7f8/library/java/zombie/iso/objects/IsoGenerator.lua
- **R4 — Vehicle refueling action annotations:** https://github.com/PZ-Umbrella/Umbrella/blob/13d01f9ee58fa48773553920db56d06f0005e7f8/library/lua/shared/Vehicles/TimedActions/ISAddGasolineToVehicle.lua
- **R5 — FuelCraft author page:** https://steamcommunity.com/sharedfiles/filedetails/?id=3757968563
- **R6 — Industrial Distillery & Biofuel System author page:** https://steamcommunity.com/workshop/filedetails/?id=3721068590&l=english
- **R7 — Gasoline Goes Bad author page:** https://steamcommunity.com/sharedfiles/filedetails/?id=3683305058
- **R8 — Alternative fuel conversions:** https://afdc.energy.gov/vehicles/conversions-basics
- **R9 — Ethanol basics:** https://afdc.energy.gov/fuels/ethanol-fuel-basics
- **R10 — Biodiesel basics:** https://afdc.energy.gov/fuels/biodiesel-basics
- **R11 — Producer gas and engine compatibility:** https://www.fao.org/4/t0512e/T0512e08.htm
- **R12 — Biogas applications:** https://www.epa.gov/anaerobic-digestion/types-anaerobic-digesters
- **R13 — Propane basics:** https://afdc.energy.gov/fuels/propane-basics

Evidence categories used in this plan:
- API annotation: a documented interface candidate, not runtime proof.
- Author description: evidence of an existing mod's stated features, not compatibility certification.
- Proposed design: internal architecture, game rules, budgets and scope choices.
- Required runtime verification: behavior to prove in M0 and subsequent acceptance tests.

No installed-game asset audit, runtime integration test or implemented mod is claimed by this document.

