# The Last Gallon — player guide

Development build for Project Zomboid 42.21.0. Features marked *(untested in
game)* are implemented but have not been verified in a running game yet.

## Why fuel behaves differently

Fuel left behind by the old world slowly goes stale. How fast depends on what
it is, how it is stored, how warm it gets and whether the container is
sealed. There is no single expiry day: some cans are fine for months, others
are already weathered when you find them. Mixing a little fresh fuel into a
big tank of stale fuel only helps a little.

Two different problems:

* **Ageing (chemical condition)** – good → weathered → poor → unsuitable.
  Cannot be filtered out. Stabilizer slows future ageing; cool, sealed
  storage helps most.
* **Contamination** – water, sediment and (for diesel) microbial sludge.
  These can be drained or filtered.

## Inspecting fuel

Right-click a fuel can → **Fuel (The Last Gallon)**:

* **Look and smell** – rough estimate, only obvious water.
* **Take a sample (kit)** – needs a *Fuel Sampling Kit* (3 empty jars +
  rubber hose). Better estimate, finds smaller amounts of water, shows the
  blend composition. Mechanics skill improves precision.
* **What I know about it** – your last result. "Unknown" means *not
  sampled*, not *bad*. Results go stale when the fuel changes.

## Treatments

* **Add stabilizer** – one bottle treats 20 L. More than a full dose does
  nothing extra. Craft from charcoal and an empty jar.
* **Filter** – needs a *Fuel Filter Cartridge* (rags, charcoal, jar).
  Removes sediment, some free water and sludge; a little fuel stays in the
  filter. Does not fix ageing.
* **Let settle and drain water** – removes free water. In a gasoline/ethanol
  blend with too much water the blend separates; the drained layer then takes
  ethanol with it.
* **Seal / Open** – open containers age faster and pick up moisture.
* **Clean empty container** – removes old residue so it cannot spoil new fuel.

## Engines

Stock gasoline engines are happy with up to 15 % ethanol, struggle up to
25 %, and will not run on more. A converted (flex) engine runs on any
gasoline/ethanol blend but starts poorly on near-pure ethanol in the cold.
Stale, wet or dirty fuel makes starting harder, costs power and wears the
engine; very bad fuel will not run at all. *(Vehicle and generator effects:
untested in game.)*

## Your first sustainable fuel: ethanol

1. **Fermentation vessel** – planks, nails, an empty jar (Carpentry 2).
   Place it on the ground, carry feedstock (sugar, corn, potatoes, sugar
   beets, pumpkins, watermelons, fruit), clean water and yeast, choose
   **Load mash and start fermenting**. About 4 days at room temperature;
   slower in the cold, stalls below ~8 °C and spoils if stalled for 3 days.
2. **Pot still** – a cooking pot, two metal pipes, a rubber hose
   (screwdriver). Place it within two tiles of a finished fermenter, **Load
   wash**, **Feed the firebox** with firewood, logs, planks or twigs.
3. **Collect ethanol into a fuel can**. A pot still gives ~80 % ethanol; a
   **reflux column still** (welding) gives ~94 % and recovers more.
4. Save the **yeast starter culture** from batches of 5 kg sugar or more –
   it replaces bought yeast.
5. For blending with gasoline, dry the ethanol in a **drying column** with
   quicklime; wet ethanol in gasoline separates.

Picking up a working machine pauses it; put it down to continue. *(Machines:
untested in game.)*

## Stations

Pumps hold old fuel that ages underground (slowly) and may contain water and
sediment from the start. TLG keeps pump accounting consistent: every litre
you take leaves the reservoir exactly once. *(Untested in game.)*

## Troubleshooting

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| "Condition unknown" | never sampled | Look/smell or use a sampling kit |
| Engine will not start on fresh-looking fuel | too much ethanol for a stock engine, or water | Sample; drain water; use gasoline or convert the engine |
| Fermenter paused "too cold" | below ~8 °C | Move it indoors / warm room |
| Still paused "firebox out of fuel" | wood ran out | Feed the firebox |
| Machine paused "picked up" | it was carried | Place it on the ground |

## Existing saves

Choose the "Existing saves" sandbox option before loading an existing world
with the mod. The default eases ageing in over 30 days.

## Removing the mod

Use up or discard ethanol, diesel, biodiesel and contaminated fuel first and
empty TLG machines. See `docs/migrations.md`.
