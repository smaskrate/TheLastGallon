# The Last Gallon — player guide

Version 0.1.0, for Project Zomboid 42.21.0. Features marked *(untested in
game)* are implemented but have not been verified in a running game yet.

## Installing

* **From the zip:** copy the folder `Contents/mods/TheLastGallon` out of the
  zip into the `mods` folder of your Project Zomboid user folder
  (`%UserProfile%\Zomboid\mods` on Windows, `~/Zomboid/mods` on Linux and
  macOS), then enable *The Last Gallon* in the game's **Mods** menu.
* **Steam Workshop:** not published.
* **An existing world:** pick the save on the load screen, press
  **Choose Mods...** and add *The Last Gallon* (see *Existing saves*
  below for the fuel already in that world).
* **Removing:** read *Removing the mod* below first.

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
* **What I know about it** – each test you have done on this fuel, the
  more precise first: your latest kit sample and your latest look and
  smell, each with how long ago you did it and what it found (a look no
  longer replaces what a kit found). Under a test it says when fuel was
  poured in or out or treated, or the container opened or closed, since
  then; and when the container is open, that the fuel may have changed
  since, so its actual condition may differ. "Unknown" means *not
  sampled*, not *bad*. What you know belongs to your character: a new
  survivor starts knowing nothing. *(Checked in game, in single player
  and on a server.)*

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
Stale, wet or dirty fuel makes starting harder, and a car running on it has
less power, never below half: it picks up speed more slowly. The power
comes back once the engine stops or gets good fuel. (The mechanics window,
which opens while the car stands still, lists the engine's power; it was
not looked at in game while lowered.) Stale or dirty fuel also
wears car and generator engines faster, a little for every litre they burn
on it. A generator's loss shows the next time you refuel, move or switch
it. Very bad fuel will not run at all. With the sandbox option "Bad fuel
can stall engines" off, cars neither refuse to start nor stall because of
their fuel, but such fuel still costs them power. *(Checked in game:
refused starts and stalls on unsuitable fuel, also on the move (the car
rolls to a stop), and a converted car and generator running on home-made
ethanol. A car burns fuel at the game's own rate while driving, the mod
takes nothing extra, and the tank keeps its blend. On stale petrol a car
ran at 85 % of its power, got it back when stopped, and its engine wore
for the litres it burned. With the option off, a car on unsuitable fuel ran
at half power without stalling. A generator on stale petrol was worn when
next refuelled.)*

## The field manual

The *Field Manual: Fuel Systems* turns up in gas station storage, garage
and mechanic shelves, farms, generator crates, bookstores, tool stores and
libraries. Choose **Inspect** to read it: one page sums up how to start
making ethanol, which engines take which fuel, and what to do when a
machine or engine stops. The notebook button at the bottom of its window
shows the same text in larger print. It teaches no recipe; everything on
it is also in this guide. *(Checked in game, in English and Italian:
manuals rolled from the loot lists as the game fills containers, and one
read through Inspect.)*

## Your first sustainable fuel: ethanol

Build the machines from the crafting window (the button beside your
equipped items) or from the craft entry of an ingredient's inventory
menu. In the window they are listed as *Make Fermentation Vessel*, *Make
Pot Still*, *Make Reflux Column Still* and *Make Ethanol Drying Column*;
the search box finds them by name. The fermentation vessel, pot still and
drying column need a table or counter within two tiles; the reflux still
is welded in hand. *(Checked in game: all of the mod's recipes found by
name in the crafting window and made with its Craft button or by
double-clicking them, the machines and the sampling kit, filter and
stabilizer alike; with an ingredient missing, Craft stays disabled. The
window was run in English; the Italian names were checked as the game
reads them.)*

1. **Fermentation vessel** – six planks, twelve nails, an empty jar and a
   hammer (Carpentry 2). It is carried in both hands, one at a time, like
   a generator, and you see it held in front of you: double-click or drag
   it in the loot window to pick it up, and it goes down at your feet when
   you get into a vehicle, take another heavy item or equip a weapon, and
   before anything with its own animation, such as looting, eating or
   dressing. If you die carrying it, it falls at your feet and its batch
   goes on there (checked in game). Place it on the
   ground, carry feedstock (sugar, corn, potatoes, sugar beets, pumpkins,
   watermelons, fruit), clean water
   and yeast, choose **Load mash and start fermenting**: it takes 5 L of
   water per kg of sugar. About 4 days when warm. A machine has the
   temperature of where it stands, averaged over the day: outdoors the
   outdoor air; in a room part of the way to 22 °C (in January 10–13 °C
   above the outdoor air; 22 °C while the power grid is on); warmer beside
   a lit fireplace, wood stove, campfire or barbecue.
   Fermenting slows below 18 °C and stops below 8 °C, and a batch stopped
   for 3 days in all spoils. In a freezing spell a room alone is not
   enough: keep a fireplace or fire well fed near the fermenter. The more
   fuel, the farther its warmth reaches, to the tiles it can see: a
   fireplace up to 8 tiles with an hour of fuel, a campfire up to 10 with
   six hours. A barbecue's warmth is milder and reaches 3 tiles: outdoors
   in January a fermenter one tile away averaged 1–8 °C a day over two
   tests, too cold to ferment most of the time. A log burns 6 hours and a fire holds at most 8 hours
   of fuel (default settings), so a log only fits once 2 hours or less are
   left: a fire kept going takes about 4 logs a day. The fire burns on
   while you are away, and its warmth still counts for as long as its fuel
   lasts (at most 8 hours): feed it a few minutes before you go. Stay away
   longer and the batch cools, and the fire will be out when you return.
   A campfire's reach shrinks as it burns down (5 tiles with 3 hours
   left, 2 with under 1¾ hours), and that counts while you are away too:
   feed it well before you go.
   **Status** shows the temperature at the machine.
2. **Pot still** – a cooking pot, two metal pipes, a rubber hose
   (screwdriver). Place it within two tiles of a finished fermenter, **Load
   wash**, **Feed the firebox**: it burns all the wood you carry (firewood,
   logs, twigs, planks too) up to what fits, so leave building planks
   behind. The pot still takes up to 60 L of wash at a time: collect the
   ethanol, then **Load wash** again for the rest. Three logs (27 kg)
   distil about 60 L; the firebox holds 30 kg, so a fourth log stays in
   your bag.
3. **Collect ethanol into a fuel can**: the still fills an empty fuel can,
   or one that already holds only ethanol, never a can with other fuel in
   it. A pot still gives ~80 % ethanol; a **reflux column still** (the pot
   still, two sheets of metal, three metal pipes, a blowtorch and a welding
   mask) gives ~94 % and recovers more.
4. Save the **yeast starter culture** from batches of 5 kg sugar or more –
   it replaces bought yeast. It comes with the last of the wash, so with a
   big batch and a pot still it appears on the second **Load wash**.
5. **Drying column** – a metal pipe and an empty jar (screwdriver). Place
   it, carry the can of ethanol and quicklime, choose **Dry ethanol with
   quicklime** and collect the result into a fuel can after about 12 hours.
   Pot-still ethanol holds too much water for any engine until it is dried.
   Reflux ethanol runs converted engines as it is, but dry it before
   blending with gasoline: wet ethanol in gasoline separates.

Picking up a working machine pauses it; put it down to continue. The hours
it stood count, the hours you carry it do not (in multiplayer up to ten
minutes before a pickup can be lost; multiplayer itself not checked).

**Pause** holds a batch where it is and **Resume** carries on, but a paused
fermenter still counts towards the 3 days that spoil it. **Abort batch**
stops a batch and keeps what it made so far: a fermenter's weaker wash for
a still, a still's spirit, a drying column's ethanol. The rest (a still's
undistilled wash, spent lime) is thrown away, and the message lists both.
A still makes no spirit while it heats up (its first hour), so a still
aborted then keeps nothing and its wash is thrown away.
Abort batch again to throw the kept part away too; a spoiled batch is
emptied the same way.

*(Building the four machines and one batch through the fermenter, reflux
still and drying column, using the menu entries named above, were checked
in game, as were January batches outdoors, in a room and on a tile warmed
by a heat source added for the test (the first two stopped and spoiled,
the warmed one finished), and a January batch beside a house fireplace
kept fed with logs (it finished; the fire was lit and fed by the test
without its menu, and its warmth counted through the first 6 hours of a
12 hour absence, as long as its fuel lasted), working fermenters, both
stills and the drying column picked up and put down again (paused while
carried, working again once down, the hours they stood counted to the
minute and the hours carried not at all, a still's firewood burning only
while it stands),
and a 12 kg batch through the pot still in two loads (its firebox left to
run out and fed again, the yeast starter coming with the last of the
wash; the spirit was unfit for any engine until dried and then fit for
flex engines, by the mod's start check, not an engine start), and Pause,
Resume and Abort batch on fermenters, a drying column and running stills
(as described above; a pot still took a stopped fermenter's wash, a
spoiled fermenter was emptied and loaded again, a still paused for three
hours burned no wood meanwhile, and a still aborted while distilling kept
only the spirit it had made), and January fermenters outdoors beside a
campfire and beside a barbecue, both fires fed and lit from their menus;
the warmth of both counted over a 12 hour absence for as long as their
fuel lasted. A campfire built indoors, a propane barbecue, upper floors
and stopped days adding up across separate cold spells are untested in
game.)*

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
   helper can work alongside you. There is no progress bar: **Project
   status** shows which stage the work has reached.
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
the basic generator were converted in game from this menu: the walk to the
engine, the work stopping once the character was out of reach and ending
when a tool was missing; both then ran on ethanol. Cancelling, removing and
the other models are untested in game.)*

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
| Car slow to pick up speed | stale, wet or dirty fuel lowers its power while the engine runs (it comes back when the engine stops) | Sample; drain water or filter it; use better fuel |
| Fermenter paused "too cold" | below 8 °C at the machine today (see Status) | Move it into a room, or beside a lit fireplace, wood stove or campfire (a barbecue is too weak outdoors on a frosty day); away, a fire keeps it warm only while its fuel lasts. After 3 days paused in all the batch spoils |
| Still paused "firebox out of fuel" | wood ran out | Feed the firebox |
| Fermenter says "Wash is left" | the still holds 60 L (pot) or 120 L (reflux) | Collect the still's ethanol, then Load wash again |
| Machine paused "picked up" | it was carried | Place it on the ground |
| Fermenter "Faulted", "the batch spoiled while stalled" | stopped for 3 days in all, hand pauses included | Abort batch empties it; then load a new mash |

## Existing saves

Add the mod to a save with the load screen's **Choose Mods...**. The fuel
already in that world is eased in over 30 days:

* Fuel the mod records in the first days, when you first look at it,
  pour it or refuel with it, starts almost fresh.
* Fuel you first touch later starts more aged.
* From 30 days after installation, fuel starts as aged as the world.

Once recorded, fuel ages from there like any other. A single-player save
takes the mod's default for this ("Existing saves", the transition
period); the load screen has no setting for it. *(Checked in game: a
world played 10 days without the mod. A can first looked at and a station
pump recorded at installation were fresh, the look was remembered, and a
can first used 6 days later was a fifth of the way to the world's age.
The other two settings and servers are untested in game.)*

## Removing the mod

The mod's machines and fuels do not survive its removal. When the game
loads a save without the mod it drops, without a word, what it no longer
knows: the mod's items (the machines with their batches, empty or not) and
the mod's fluids in any container. Before you remove it, use up what you
want to keep: ethanol, diesel, biodiesel, and contaminated fuel (its water
and sediment are the mod's fluids too). The machines cannot be kept. Stop
every car running on poor fuel before your last save with the mod: a car
saved running keeps its lowered power without the mod, until a repair.

Petrol stays, and so does what the mod recorded about it. Put the mod back
later and it finds that record as it was; the world's fuel history does
not start again, so nothing comes back fresh. Petrol poured out of a can
meanwhile leaves the rest as it was. Petrol added meanwhile counts as fuel
of unknown origin, found the next time the mod sees the can. *(Checked in
game: the mod taken off a save with the load screen's Choose mods, a day
played, the mod put back. A fermenter with a batch running and a can of
ethanol were gone; a petrol can poured from and one topped up read as
described. The mod's other fluids and items, converted engines, and a save
whose mod was uninstalled, where the game asks about missing mods, were
not tried.)* See `docs/migrations.md`.
