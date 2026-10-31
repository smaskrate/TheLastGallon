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
engine; very bad fuel will not run at all. *(Checked in game: refused starts
and stalls on unsuitable fuel, and a converted car and generator running on
home-made ethanol. The effects while driving are untested in game.)*

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
5. **Drying column** – place it, carry the can of ethanol and quicklime,
   choose **Dry ethanol with quicklime** and collect the result into a fuel
   can after about 12 hours. Pot-still ethanol holds too much water for any
   engine until it is dried. Reflux ethanol runs converted engines as it is,
   but dry it before blending with gasoline: wet ethanol in gasoline
   separates.

Picking up a working machine pauses it; put it down to continue. *(One batch
through the fermenter, reflux still and drying column was checked in game;
building the machines, their menus, the pot still and picking up a working
machine are untested in game.)*

## Converting an engine

A flex conversion lets an engine run on any gasoline/ethanol blend.
Right-click the generator or car → **Workshop: convert this generator** (or
**vehicle**):

1. **Start: …** – needs the skills and recipe below and a screwdriver. The
   engine must be off.
2. **Hand over parts** – takes the listed parts from your inventory.
3. **Work on it** – your character walks to the engine (or the generator)
   and works there until the conversion is finished or something is
   missing; a message then says which. Walking away stops the work and time
   away is never counted: choose **Work on it** again to carry on. Every
   stage needs its tools (screwdriver, wrench, pliers), and the fuel tank
   must be empty while you drain the fuel system and install the parts. A
   helper can work alongside you.
4. When the status reads **Converted and commissioned**, the engine is flex.

| | Generator | Standard car |
| --- | --- | --- |
| Skills | Mechanics 2, Electrical 2 | Mechanics 4 |
| Recipe (magazine) | Generator ("How to Use Generators") | Basic Mechanics ("Laines Standard Auto Manual") |
| Parts | 1 rubber hose, 4 screws, 1 electric wire | 2 rubber hoses, 2 engine parts, 6 screws, 2 electric wires |
| Work | 7.5 hours | 13 hours |

Cancelling returns three quarters of the parts handed over; removing a
finished conversion returns half. Small cars, pickup trucks, step vans and
the other generator models have their own conversions. *(A standard car and
the basic generator were converted in game, the work stopped once the
character was out of reach, and both then ran on ethanol. The menu entries
themselves, walking to the device, the work ending because something is
missing, cancelling, removing and the other models are untested in game.)*

## Stations

Pumps hold old fuel that ages underground (slowly). Most stations hold only a
trace of water, but about one in ten is contaminated: its fuel makes a stock
car hard to start until you drain the water or dilute it with cleaner fuel.
Sample before you fill up at an unknown station. TLG keeps pump accounting
consistent: every litre you take leaves the reservoir exactly once (checked
in game).

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
