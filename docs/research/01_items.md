# 01 — Items & Fluids (Gearforge base set)

Source: Factorio 1.1.110 base-game prototype data (wube/factorio-data tag `1.1.110`, `base/prototypes/item.lua`, `fluid.lua`, `equipment.lua`, entity files), extracted programmatically by `docs/research/tools/gen_items.py`. Numbers are exact copies of the 1.1 prototype values (normal mode). Names: Gearforge ids are snake_case; branded names were replaced (see "Renames" below).

## Conventions

- **id** – Gearforge internal id (snake_case). **F1.1 name** – original prototype name, kept only for traceability (do not ship it).
- **group/subgroup** – crafting-menu tab / row. Group order (tabs): logistics, production, intermediate-products, combat. Within a table rows are already in in-game menu order (group order → subgroup order → item order).
- **stack** – stack size. **fuel MJ** – fuel value in megajoules (chemical fuel unless noted). **places** – entity id placed by the item (or `tile:<name>`).
- **phase** – `mvp` = in first release; `mvp*` = item needed in MVP as an ingredient although its main feature is later; `combat`, `trains`, `robots`, `nuclear`, `circuit` = later phases (see GDD §Phases).
- Science packs are called **cards** in Gearforge. Science-pack durability (1.0) is dropped: 1 card = 1 research unit ingredient.

## Renames (branded / lore names → Gearforge)

| F1.1 name | Gearforge id | Display name |
|---|---|---|
| automation-science-pack | mechanics_card | Mechanics card (red) |
| logistic-science-pack | motion_card | Motion card (green) |
| military-science-pack | defense_card | Defense card (black) |
| chemical-science-pack | reaction_card | Reaction card (blue) |
| production-science-pack | fabrication_card | Fabrication card (purple) |
| utility-science-pack | systems_card | Systems card (yellow) |
| space-science-pack | orbital_card | Orbital card (white) |
| kovarex-enrichment-process | uranium_enrichment | Uranium enrichment process |
| spidertron | strider | Strider |
| spidertron-remote | strider_remote | Strider remote |
| spidertron-rocket-launcher-1 | strider_rocket_launcher_1 | Strider rocket launcher 1 |
| spidertron-rocket-launcher-2 | strider_rocket_launcher_2 | Strider rocket launcher 2 |
| spidertron-rocket-launcher-3 | strider_rocket_launcher_3 | Strider rocket launcher 3 |
| spidertron-rocket-launcher-4 | strider_rocket_launcher_4 | Strider rocket launcher 4 |
| spidertron-leg-1 | strider_leg_1 | Strider leg |
| effectivity-module | efficiency_module | Efficiency module |
| effectivity-module-2 | efficiency_module_2 | Efficiency module 2 |
| effectivity-module-3 | efficiency_module_3 | Efficiency module 3 |
| used-up-uranium-fuel-cell | depleted_uranium_fuel_cell | Depleted uranium fuel cell |
| fusion-reactor-equipment | portable_fusion_reactor | Portable fusion reactor |
| logistic-chest-active-provider | active_provider_chest | Active provider chest |
| logistic-chest-passive-provider | passive_provider_chest | Passive provider chest |
| logistic-chest-storage | storage_chest | Storage chest |
| logistic-chest-buffer | buffer_chest | Buffer chest |
| logistic-chest-requester | requester_chest | Requester chest |
| character | character | Engineer (player character) |

## Intermediate products & raw resources (48)

| id | display name | group/subgroup | stack | fuel MJ | places | phase | notes | F1.1 name |
|---|---|---|---|---|---|---|---|---|
| wood | Wood | intermediate-products/raw-resource | 100 | 2 | - | mvp | fuel category: chemical; not craftable (raw / mined / launch product) | wood |
| coal | Coal | intermediate-products/raw-resource | 50 | 4 | - | mvp | fuel category: chemical; not craftable (raw / mined / launch product) | coal |
| stone | Stone | intermediate-products/raw-resource | 50 | - | - | mvp | not craftable (raw / mined / launch product) | stone |
| iron_ore | Iron ore | intermediate-products/raw-resource | 50 | - | - | mvp | not craftable (raw / mined / launch product) | iron-ore |
| copper_ore | Copper ore | intermediate-products/raw-resource | 50 | - | - | mvp | not craftable (raw / mined / launch product) | copper-ore |
| uranium_ore | Uranium ore | intermediate-products/raw-resource | 50 | - | - | nuclear | not craftable (raw / mined / launch product) | uranium-ore |
| raw_fish | Raw fish | intermediate-products/raw-resource | 100 | - | - | combat | capsule (usable); not craftable (raw / mined / launch product) | raw-fish |
| iron_plate | Iron plate | intermediate-products/raw-material | 100 | - | - | mvp |  | iron-plate |
| copper_plate | Copper plate | intermediate-products/raw-material | 100 | - | - | mvp |  | copper-plate |
| solid_fuel | Solid fuel | intermediate-products/raw-material | 50 | 12 | - | mvp | fuel category: chemical; vehicle accel x1.2; vehicle top speed x1.05 | solid-fuel |
| steel_plate | Steel plate | intermediate-products/raw-material | 100 | - | - | mvp |  | steel-plate |
| plastic_bar | Plastic bar | intermediate-products/raw-material | 100 | - | - | mvp |  | plastic-bar |
| sulfur | Sulfur | intermediate-products/raw-material | 50 | - | - | mvp |  | sulfur |
| battery | Battery | intermediate-products/raw-material | 200 | - | - | mvp |  | battery |
| explosives | Explosives | intermediate-products/raw-material | 50 | - | - | combat |  | explosives |
| crude_oil_barrel | Crude oil barrel | intermediate-products/barrel | 10 | - | - | mvp |  | crude-oil-barrel |
| heavy_oil_barrel | Heavy oil barrel | intermediate-products/barrel | 10 | - | - | mvp |  | heavy-oil-barrel |
| light_oil_barrel | Light oil barrel | intermediate-products/barrel | 10 | - | - | mvp |  | light-oil-barrel |
| lubricant_barrel | Lubricant barrel | intermediate-products/barrel | 10 | - | - | mvp |  | lubricant-barrel |
| petroleum_gas_barrel | Petroleum gas barrel | intermediate-products/barrel | 10 | - | - | mvp |  | petroleum-gas-barrel |
| sulfuric_acid_barrel | Sulfuric acid barrel | intermediate-products/barrel | 10 | - | - | mvp |  | sulfuric-acid-barrel |
| water_barrel | Water barrel | intermediate-products/barrel | 10 | - | - | mvp |  | water-barrel |
| copper_cable | Copper cable | intermediate-products/intermediate-product | 200 | - | - | mvp |  | copper-cable |
| iron_stick | Iron stick | intermediate-products/intermediate-product | 100 | - | - | mvp |  | iron-stick |
| iron_gear_wheel | Iron gear wheel | intermediate-products/intermediate-product | 100 | - | - | mvp |  | iron-gear-wheel |
| empty_barrel | Empty barrel | intermediate-products/intermediate-product | 10 | - | - | mvp |  | empty-barrel |
| electronic_circuit | Electronic circuit | intermediate-products/intermediate-product | 200 | - | - | mvp |  | electronic-circuit |
| advanced_circuit | Advanced circuit | intermediate-products/intermediate-product | 200 | - | - | mvp |  | advanced-circuit |
| processing_unit | Processing unit | intermediate-products/intermediate-product | 100 | - | - | mvp |  | processing-unit |
| engine_unit | Engine unit | intermediate-products/intermediate-product | 50 | - | - | mvp |  | engine-unit |
| electric_engine_unit | Electric engine unit | intermediate-products/intermediate-product | 50 | - | - | mvp |  | electric-engine-unit |
| flying_robot_frame | Flying robot frame | intermediate-products/intermediate-product | 50 | - | - | mvp |  | flying-robot-frame |
| rocket_control_unit | Rocket control unit | intermediate-products/intermediate-product | 10 | - | - | mvp |  | rocket-control-unit |
| low_density_structure | Low density structure | intermediate-products/intermediate-product | 10 | - | - | mvp |  | low-density-structure |
| rocket_fuel | Rocket fuel | intermediate-products/intermediate-product | 10 | 100 | - | mvp | fuel category: chemical; vehicle accel x1.8; vehicle top speed x1.15 | rocket-fuel |
| rocket_part | Rocket part | intermediate-products/intermediate-product | 5 | - | - | mvp | hidden item: exists only inside the rocket silo (100 parts = 1 rocket) | rocket-part |
| nuclear_fuel | Nuclear fuel | intermediate-products/intermediate-product | 1 | 1210 | - | nuclear | fuel category: chemical; vehicle accel x2.5; vehicle top speed x1.15 | nuclear-fuel |
| uranium_235 | Uranium-235 | intermediate-products/intermediate-product | 100 | - | - | nuclear |  | uranium-235 |
| uranium_238 | Uranium-238 | intermediate-products/intermediate-product | 100 | - | - | nuclear |  | uranium-238 |
| uranium_fuel_cell | Uranium fuel cell | intermediate-products/intermediate-product | 50 | 8000 | - | nuclear | fuel category: nuclear; burnt result: depleted_uranium_fuel_cell | uranium-fuel-cell |
| depleted_uranium_fuel_cell | Depleted uranium fuel cell | intermediate-products/intermediate-product | 50 | - | - | nuclear | not craftable (raw / mined / launch product) | used-up-uranium-fuel-cell |
| mechanics_card | Mechanics card (red) | intermediate-products/science-pack | 200 | - | - | mvp | science pack (research ingredient) | automation-science-pack |
| motion_card | Motion card (green) | intermediate-products/science-pack | 200 | - | - | mvp | science pack (research ingredient) | logistic-science-pack |
| defense_card | Defense card (black) | intermediate-products/science-pack | 200 | - | - | combat | science pack (research ingredient) | military-science-pack |
| reaction_card | Reaction card (blue) | intermediate-products/science-pack | 200 | - | - | mvp | science pack (research ingredient) | chemical-science-pack |
| fabrication_card | Fabrication card (purple) | intermediate-products/science-pack | 200 | - | - | mvp | science pack (research ingredient) | production-science-pack |
| systems_card | Systems card (yellow) | intermediate-products/science-pack | 200 | - | - | mvp | science pack (research ingredient) | utility-science-pack |
| orbital_card | Orbital card (white) | intermediate-products/science-pack | 2000 | - | - | mvp | science pack (research ingredient); rocket launch product: 1 x raw_fish; not craftable (raw / mined / launch product) | space-science-pack |

## Logistics (62)

| id | display name | group/subgroup | stack | fuel MJ | places | phase | notes | F1.1 name |
|---|---|---|---|---|---|---|---|---|
| wooden_chest | Wooden chest | logistics/storage | 50 | - | wooden_chest | mvp |  | wooden-chest |
| iron_chest | Iron chest | logistics/storage | 50 | - | iron_chest | mvp |  | iron-chest |
| steel_chest | Steel chest | logistics/storage | 50 | - | steel_chest | mvp |  | steel-chest |
| storage_tank | Storage tank | logistics/storage | 50 | - | storage_tank | mvp |  | storage-tank |
| transport_belt | Transport belt | logistics/belt | 100 | - | transport_belt | mvp |  | transport-belt |
| fast_transport_belt | Fast transport belt | logistics/belt | 100 | - | fast_transport_belt | mvp |  | fast-transport-belt |
| express_transport_belt | Express transport belt | logistics/belt | 100 | - | express_transport_belt | mvp |  | express-transport-belt |
| underground_belt | Underground belt | logistics/belt | 50 | - | underground_belt | mvp |  | underground-belt |
| fast_underground_belt | Fast underground belt | logistics/belt | 50 | - | fast_underground_belt | mvp |  | fast-underground-belt |
| express_underground_belt | Express underground belt | logistics/belt | 50 | - | express_underground_belt | mvp |  | express-underground-belt |
| splitter | Splitter | logistics/belt | 50 | - | splitter | mvp |  | splitter |
| fast_splitter | Fast splitter | logistics/belt | 50 | - | fast_splitter | mvp |  | fast-splitter |
| express_splitter | Express splitter | logistics/belt | 50 | - | express_splitter | mvp |  | express-splitter |
| burner_inserter | Burner inserter | logistics/inserter | 50 | - | burner_inserter | mvp |  | burner-inserter |
| inserter | Inserter | logistics/inserter | 50 | - | inserter | mvp |  | inserter |
| long_handed_inserter | Long handed inserter | logistics/inserter | 50 | - | long_handed_inserter | mvp |  | long-handed-inserter |
| fast_inserter | Fast inserter | logistics/inserter | 50 | - | fast_inserter | mvp |  | fast-inserter |
| filter_inserter | Filter inserter | logistics/inserter | 50 | - | filter_inserter | mvp |  | filter-inserter |
| stack_inserter | Stack inserter | logistics/inserter | 50 | - | stack_inserter | mvp |  | stack-inserter |
| stack_filter_inserter | Stack filter inserter | logistics/inserter | 50 | - | stack_filter_inserter | mvp |  | stack-filter-inserter |
| small_electric_pole | Small electric pole | logistics/energy-pipe-distribution | 50 | - | small_electric_pole | mvp |  | small-electric-pole |
| medium_electric_pole | Medium electric pole | logistics/energy-pipe-distribution | 50 | - | medium_electric_pole | mvp |  | medium-electric-pole |
| big_electric_pole | Big electric pole | logistics/energy-pipe-distribution | 50 | - | big_electric_pole | mvp |  | big-electric-pole |
| substation | Substation | logistics/energy-pipe-distribution | 50 | - | substation | mvp |  | substation |
| pipe | Pipe | logistics/energy-pipe-distribution | 100 | - | pipe | mvp |  | pipe |
| pipe_to_ground | Pipe to ground | logistics/energy-pipe-distribution | 50 | - | pipe_to_ground | mvp |  | pipe-to-ground |
| pump | Pump | logistics/energy-pipe-distribution | 50 | - | pump | mvp |  | pump |
| rail | Rail | logistics/train-transport | 100 | - | straight_rail | mvp* | rail planner | rail |
| train_stop | Train stop | logistics/train-transport | 10 | - | train_stop | trains |  | train-stop |
| rail_signal | Rail signal | logistics/train-transport | 50 | - | rail_signal | trains |  | rail-signal |
| rail_chain_signal | Rail chain signal | logistics/train-transport | 50 | - | rail_chain_signal | trains |  | rail-chain-signal |
| locomotive | Locomotive | logistics/train-transport | 5 | - | locomotive | trains | vehicle item | locomotive |
| cargo_wagon | Cargo wagon | logistics/train-transport | 5 | - | cargo_wagon | trains | vehicle item | cargo-wagon |
| fluid_wagon | Fluid wagon | logistics/train-transport | 5 | - | fluid_wagon | trains | vehicle item | fluid-wagon |
| artillery_wagon | Artillery wagon | logistics/train-transport | 5 | - | artillery_wagon | trains | vehicle item | artillery-wagon |
| car | Car | logistics/transport | 1 | - | car | combat | vehicle item | car |
| tank | Tank | logistics/transport | 1 | - | tank | combat | vehicle item | tank |
| strider | Strider | logistics/transport | 1 | - | strider | combat | vehicle item | spidertron |
| strider_remote | Strider remote | logistics/transport | 1 | - | - | combat |  | spidertron-remote |
| logistic_robot | Logistic robot | logistics/logistic-network | 50 | - | logistic_robot | robots |  | logistic-robot |
| construction_robot | Construction robot | logistics/logistic-network | 50 | - | construction_robot | robots |  | construction-robot |
| active_provider_chest | Active provider chest | logistics/logistic-network | 50 | - | active_provider_chest | robots |  | logistic-chest-active-provider |
| passive_provider_chest | Passive provider chest | logistics/logistic-network | 50 | - | passive_provider_chest | robots |  | logistic-chest-passive-provider |
| storage_chest | Storage chest | logistics/logistic-network | 50 | - | storage_chest | robots |  | logistic-chest-storage |
| buffer_chest | Buffer chest | logistics/logistic-network | 50 | - | buffer_chest | robots |  | logistic-chest-buffer |
| requester_chest | Requester chest | logistics/logistic-network | 50 | - | requester_chest | robots |  | logistic-chest-requester |
| roboport | Roboport | logistics/logistic-network | 10 | - | roboport | robots |  | roboport |
| small_lamp | Lamp | logistics/circuit-network | 50 | - | small_lamp | mvp |  | small-lamp |
| red_wire | Red wire | logistics/circuit-network | 200 | - | - | circuit |  | red-wire |
| green_wire | Green wire | logistics/circuit-network | 200 | - | - | circuit |  | green-wire |
| arithmetic_combinator | Arithmetic combinator | logistics/circuit-network | 50 | - | arithmetic_combinator | circuit |  | arithmetic-combinator |
| decider_combinator | Decider combinator | logistics/circuit-network | 50 | - | decider_combinator | circuit |  | decider-combinator |
| constant_combinator | Constant combinator | logistics/circuit-network | 50 | - | constant_combinator | circuit |  | constant-combinator |
| power_switch | Power switch | logistics/circuit-network | 50 | - | power_switch | circuit |  | power-switch |
| programmable_speaker | Programmable speaker | logistics/circuit-network | 50 | - | programmable_speaker | circuit |  | programmable-speaker |
| stone_brick | Stone brick | logistics/terrain | 100 | - | tile:stone-path | mvp | places tile 'stone-path' on land only (blocked by water) | stone-brick |
| concrete | Concrete | logistics/terrain | 100 | - | tile:concrete | mvp | places tile 'concrete' on land only (blocked by water) | concrete |
| hazard_concrete | Hazard concrete | logistics/terrain | 100 | - | tile:hazard-concrete-left | mvp | places tile 'hazard-concrete-left' on land only (blocked by water) | hazard-concrete |
| refined_concrete | Refined concrete | logistics/terrain | 100 | - | tile:refined-concrete | mvp | places tile 'refined-concrete' on land only (blocked by water) | refined-concrete |
| refined_hazard_concrete | Refined hazard concrete | logistics/terrain | 100 | - | tile:refined-hazard-concrete-left | mvp | places tile 'refined-hazard-concrete-left' on land only (blocked by water) | refined-hazard-concrete |
| landfill | Landfill | logistics/terrain | 100 | - | tile:landfill | mvp | places tile 'landfill' on WATER only (turns water into land) | landfill |
| cliff_explosives | Cliff explosives | logistics/terrain | 20 | - | - | combat | capsule (usable) | cliff-explosives |

## Production (35)

| id | display name | group/subgroup | stack | fuel MJ | places | phase | notes | F1.1 name |
|---|---|---|---|---|---|---|---|---|
| repair_pack | Repair pack | production/tool | 100 | - | - | combat | repair tool; speed 2, durability 300 | repair-pack |
| boiler | Boiler | production/energy | 50 | - | boiler | mvp |  | boiler |
| steam_engine | Steam engine | production/energy | 10 | - | steam_engine | mvp |  | steam-engine |
| solar_panel | Solar panel | production/energy | 50 | - | solar_panel | mvp |  | solar-panel |
| accumulator | Accumulator | production/energy | 50 | - | accumulator | mvp |  | accumulator |
| nuclear_reactor | Nuclear reactor | production/energy | 10 | - | nuclear_reactor | nuclear |  | nuclear-reactor |
| heat_pipe | Heat pipe | production/energy | 50 | - | heat_pipe | nuclear |  | heat-pipe |
| heat_exchanger | Heat exchanger | production/energy | 50 | - | heat_exchanger | nuclear |  | heat-exchanger |
| steam_turbine | Steam turbine | production/energy | 10 | - | steam_turbine | nuclear |  | steam-turbine |
| burner_mining_drill | Burner mining drill | production/extraction-machine | 50 | - | burner_mining_drill | mvp |  | burner-mining-drill |
| electric_mining_drill | Electric mining drill | production/extraction-machine | 50 | - | electric_mining_drill | mvp |  | electric-mining-drill |
| offshore_pump | Offshore pump | production/extraction-machine | 20 | - | offshore_pump | mvp |  | offshore-pump |
| pumpjack | Pumpjack | production/extraction-machine | 20 | - | pumpjack | mvp |  | pumpjack |
| stone_furnace | Stone furnace | production/smelting-machine | 50 | - | stone_furnace | mvp |  | stone-furnace |
| steel_furnace | Steel furnace | production/smelting-machine | 50 | - | steel_furnace | mvp |  | steel-furnace |
| electric_furnace | Electric furnace | production/smelting-machine | 50 | - | electric_furnace | mvp |  | electric-furnace |
| assembling_machine_1 | Assembling machine 1 | production/production-machine | 50 | - | assembling_machine_1 | mvp |  | assembling-machine-1 |
| assembling_machine_2 | Assembling machine 2 | production/production-machine | 50 | - | assembling_machine_2 | mvp |  | assembling-machine-2 |
| assembling_machine_3 | Assembling machine 3 | production/production-machine | 50 | - | assembling_machine_3 | mvp |  | assembling-machine-3 |
| oil_refinery | Oil refinery | production/production-machine | 10 | - | oil_refinery | mvp |  | oil-refinery |
| chemical_plant | Chemical plant | production/production-machine | 10 | - | chemical_plant | mvp |  | chemical-plant |
| centrifuge | Centrifuge | production/production-machine | 50 | - | centrifuge | nuclear |  | centrifuge |
| lab | Lab | production/production-machine | 10 | - | lab | mvp |  | lab |
| beacon | Beacon | production/module | 10 | - | beacon | mvp |  | beacon |
| speed_module | Speed module | production/module | 50 | - | - | mvp | module; effects: consumption +50%, speed +20% | speed-module |
| speed_module_2 | Speed module 2 | production/module | 50 | - | - | mvp | module; effects: consumption +60%, speed +30% | speed-module-2 |
| speed_module_3 | Speed module 3 | production/module | 50 | - | - | mvp | module; effects: consumption +70%, speed +50% | speed-module-3 |
| efficiency_module | Efficiency module | production/module | 50 | - | - | mvp | module; effects: consumption -30% | effectivity-module |
| efficiency_module_2 | Efficiency module 2 | production/module | 50 | - | - | mvp | module; effects: consumption -40% | effectivity-module-2 |
| efficiency_module_3 | Efficiency module 3 | production/module | 50 | - | - | mvp | module; effects: consumption -50% | effectivity-module-3 |
| productivity_module | Productivity module | production/module | 50 | - | - | mvp | module; effects: consumption +40%, pollution +5%, productivity +4%, speed -5%; intermediate-only (see module limitation list in 05_mechanics) | productivity-module |
| productivity_module_2 | Productivity module 2 | production/module | 50 | - | - | mvp | module; effects: consumption +60%, pollution +7%, productivity +6%, speed -10%; intermediate-only (see module limitation list in 05_mechanics) | productivity-module-2 |
| productivity_module_3 | Productivity module 3 | production/module | 50 | - | - | mvp | module; effects: consumption +80%, pollution +10%, productivity +10%, speed -15%; intermediate-only (see module limitation list in 05_mechanics) | productivity-module-3 |
| rocket_silo | Rocket silo | production/space-related | 1 | - | rocket_silo | mvp |  | rocket-silo |
| satellite | Satellite | production/space-related | 1 | - | - | mvp | rocket launch product: 1000 x orbital_card | satellite |

## Combat (combat phase) (55)

| id | display name | group/subgroup | stack | fuel MJ | places | phase | notes | F1.1 name |
|---|---|---|---|---|---|---|---|---|
| pistol | Pistol | combat/gun | 5 | - | - | combat | weapon | pistol |
| submachine_gun | Submachine gun | combat/gun | 5 | - | - | combat | weapon | submachine-gun |
| shotgun | Shotgun | combat/gun | 5 | - | - | combat | weapon | shotgun |
| combat_shotgun | Combat shotgun | combat/gun | 5 | - | - | combat | weapon | combat-shotgun |
| rocket_launcher | Rocket launcher | combat/gun | 5 | - | - | combat | weapon | rocket-launcher |
| flamethrower | Flamethrower | combat/gun | 5 | - | - | combat | weapon | flamethrower |
| land_mine | Land mine | combat/gun | 100 | - | land_mine | combat |  | land-mine |
| firearm_magazine | Firearm magazine | combat/ammo | 200 | - | - | combat | ammo; magazine size 10 | firearm-magazine |
| piercing_rounds_magazine | Piercing rounds magazine | combat/ammo | 200 | - | - | combat | ammo; magazine size 10 | piercing-rounds-magazine |
| uranium_rounds_magazine | Uranium rounds magazine | combat/ammo | 200 | - | - | combat | ammo; magazine size 10 | uranium-rounds-magazine |
| shotgun_shell | Shotgun shell | combat/ammo | 200 | - | - | combat | ammo; magazine size 10 | shotgun-shell |
| piercing_shotgun_shell | Piercing shotgun shell | combat/ammo | 200 | - | - | combat | ammo; magazine size 10 | piercing-shotgun-shell |
| cannon_shell | Cannon shell | combat/ammo | 200 | - | - | combat | ammo | cannon-shell |
| explosive_cannon_shell | Explosive cannon shell | combat/ammo | 200 | - | - | combat | ammo | explosive-cannon-shell |
| uranium_cannon_shell | Uranium cannon shell | combat/ammo | 200 | - | - | combat | ammo | uranium-cannon-shell |
| explosive_uranium_cannon_shell | Explosive uranium cannon shell | combat/ammo | 200 | - | - | combat | ammo | explosive-uranium-cannon-shell |
| artillery_shell | Artillery shell | combat/ammo | 1 | - | - | combat | ammo | artillery-shell |
| rocket | Rocket | combat/ammo | 200 | - | - | combat | ammo | rocket |
| explosive_rocket | Explosive rocket | combat/ammo | 200 | - | - | combat | ammo | explosive-rocket |
| atomic_bomb | Atomic bomb | combat/ammo | 10 | - | - | combat | ammo | atomic-bomb |
| flamethrower_ammo | Flamethrower ammo | combat/ammo | 100 | - | - | combat | ammo; magazine size 100 | flamethrower-ammo |
| grenade | Grenade | combat/capsule | 100 | - | - | combat | capsule (usable) | grenade |
| cluster_grenade | Cluster grenade | combat/capsule | 100 | - | - | combat | capsule (usable) | cluster-grenade |
| poison_capsule | Poison capsule | combat/capsule | 100 | - | - | combat | capsule (usable) | poison-capsule |
| slowdown_capsule | Slowdown capsule | combat/capsule | 100 | - | - | combat | capsule (usable) | slowdown-capsule |
| defender_capsule | Defender capsule | combat/capsule | 100 | - | - | combat | capsule (usable) | defender-capsule |
| distractor_capsule | Distractor capsule | combat/capsule | 100 | - | - | combat | capsule (usable) | distractor-capsule |
| destroyer_capsule | Destroyer capsule | combat/capsule | 100 | - | - | combat | capsule (usable) | destroyer-capsule |
| light_armor | Light armor | combat/armor | 1 | - | - | combat | armor; inventory bonus +0; grid - | light-armor |
| heavy_armor | Heavy armor | combat/armor | 1 | - | - | combat | armor; inventory bonus +0; grid - | heavy-armor |
| modular_armor | Modular armor | combat/armor | 1 | - | - | combat | armor; inventory bonus +10; grid small-equipment-grid | modular-armor |
| power_armor | Power armor | combat/armor | 1 | - | - | combat | armor; inventory bonus +20; grid medium-equipment-grid | power-armor |
| power_armor_mk2 | Power armor MK2 | combat/armor | 1 | - | - | combat | armor; inventory bonus +30; grid large-equipment-grid | power-armor-mk2 |
| solar_panel_equipment | Portable solar panel | combat/equipment | 20 | - | - | combat | equipment: solar_panel_equipment | solar-panel-equipment |
| portable_fusion_reactor | Portable fusion reactor | combat/equipment | 20 | - | - | combat | equipment: portable_fusion_reactor | fusion-reactor-equipment |
| battery_equipment | Personal battery | combat/equipment | 20 | - | - | combat | equipment: battery_equipment | battery-equipment |
| battery_mk2_equipment | Personal battery MK2 | combat/equipment | 20 | - | - | combat | equipment: battery_mk2_equipment | battery-mk2-equipment |
| belt_immunity_equipment | Belt immunity equipment | combat/equipment | 20 | - | - | combat | equipment: belt_immunity_equipment | belt-immunity-equipment |
| exoskeleton_equipment | Exoskeleton | combat/equipment | 20 | - | - | combat | equipment: exoskeleton_equipment | exoskeleton-equipment |
| personal_roboport_equipment | Personal roboport | combat/equipment | 20 | - | - | combat | equipment: personal_roboport_equipment | personal-roboport-equipment |
| personal_roboport_mk2_equipment | Personal roboport MK2 | combat/equipment | 20 | - | - | combat | equipment: personal_roboport_mk2_equipment | personal-roboport-mk2-equipment |
| night_vision_equipment | Nightvision | combat/equipment | 20 | - | - | combat | equipment: night_vision_equipment | night-vision-equipment |
| energy_shield_equipment | Energy shield | combat/military-equipment | 20 | - | - | combat | equipment: energy_shield_equipment | energy-shield-equipment |
| energy_shield_mk2_equipment | Energy shield MK2 | combat/military-equipment | 20 | - | - | combat | equipment: energy_shield_mk2_equipment | energy-shield-mk2-equipment |
| personal_laser_defense_equipment | Personal laser defense | combat/military-equipment | 20 | - | - | combat | equipment: personal_laser_defense_equipment | personal-laser-defense-equipment |
| discharge_defense_equipment | Discharge defense | combat/military-equipment | 20 | - | - | combat | equipment: discharge_defense_equipment | discharge-defense-equipment |
| discharge_defense_remote | Discharge defense remote | combat/military-equipment | 1 | - | - | combat | capsule (usable) | discharge-defense-remote |
| stone_wall | Stone wall | combat/defensive-structure | 100 | - | stone_wall | combat |  | stone-wall |
| gate | Gate | combat/defensive-structure | 50 | - | gate | combat |  | gate |
| gun_turret | Gun turret | combat/defensive-structure | 50 | - | gun_turret | combat |  | gun-turret |
| laser_turret | Laser turret | combat/defensive-structure | 50 | - | laser_turret | combat |  | laser-turret |
| flamethrower_turret | Flamethrower turret | combat/defensive-structure | 50 | - | flamethrower_turret | combat |  | flamethrower-turret |
| artillery_turret | Artillery turret | combat/defensive-structure | 10 | - | artillery_turret | combat |  | artillery-turret |
| artillery_targeting_remote | Artillery targeting remote | combat/defensive-structure | 1 | - | - | combat | capsule (usable) | artillery-targeting-remote |
| radar | Radar | combat/defensive-structure | 50 | - | radar | mvp | menu group is combat but radar is MVP (map reveal) | radar |

## Fluids (8)

Fluids are not items: they live in fluid boxes (pipes/tanks/machines) and are measured in units. Barrels (50 units per barrel) carry fluids as items. Temperature in °C; heat capacity in kJ per unit per °C (relevant for steam: energy = units × (T − 15) × 0.2 kJ). No base fluid has a fuel value in 1.1 (fluid fuel is only modded).

| id | display name | default °C | max °C | heat cap kJ/°C | fuel MJ | barrelable | colour | phase | F1.1 name |
|---|---|---|---|---|---|---|---|---|---|
| water | Water | 15 | 100 | 0.2 | - | yes | #005799 | mvp | water |
| crude_oil | Crude oil | 25 | 25 | 0.1 | - | yes | #000000 | mvp | crude-oil |
| steam | Steam | 15 | 1000 | 0.2 | - | no | #808080 | mvp | steam |
| heavy_oil | Heavy oil | 25 | 25 | 0.1 | - | yes | #800a00 | mvp | heavy-oil |
| light_oil | Light oil | 25 | 25 | 0.1 | - | yes | #915400 | mvp | light-oil |
| petroleum_gas | Petroleum gas | 25 | 25 | 0.1 | - | yes | #4c1a4c | mvp | petroleum-gas |
| sulfuric_acid | Sulfuric acid | 25 | 25 | 0.1 | - | yes | #bfa61a | mvp | sulfuric-acid |
| lubricant | Lubricant | 25 | 25 | 0.1 | - | yes | #265208 | mvp | lubricant |

Fluid temperature notes: steam from a **boiler** is 165 °C; steam from a **heat exchanger** is 500 °C. A steam engine accepts up to 165 °C steam, a steam turbine up to 500 °C (engines/turbines fed hotter steam do not gain power beyond their maximum temperature).

## Raw resources (map resources)

| resource id | name | resource category | mining time | yield per cycle | required fluid | infinite | infinite params | phase |
|---|---|---|---|---|---|---|---|---|
| coal | Coal | basic-solid | 1 | 1 x coal | - | no | - | mvp |
| copper_ore | Copper ore | basic-solid | 1 | 1 x copper_ore | - | no | - | mvp |
| crude_oil | Crude oil | basic-fluid | 1 | 10 x crude_oil (fluid) | - | yes | min 60000, normal 300000, infinite_depletion 10 | mvp |
| iron_ore | Iron ore | basic-solid | 1 | 1 x iron_ore | - | no | - | mvp |
| stone | Stone | basic-solid | 1 | 1 x stone | - | no | - | mvp |
| uranium_ore | Uranium ore | basic-solid | 2 | 1 x uranium_ore | sulfuric_acid x10 per 10 cycles | no | - | nuclear |

Note: `fluid_amount` in the prototype is per 10 mining cycles in 1.1 convention — uranium ore needs **1 sulfuric acid per ore** in practice (fluid_amount 10 ⇒ 10 units per 10 ores). Crude oil: yield `amount` is 10 per cycle at 100% yield (300 000 = 100%); see 05_mechanics §Mining for pumpjack yield formula. Trees (wood: 4 per tree, mining time 0.55 for most tree types) and rocks (stone/coal) are minable world objects: see 05_mechanics §Resource generation.

## Excluded / not shipped (35)

Editor/debug/hidden items and blueprint-family tools. Blueprints, deconstruction & upgrade planners are re-specified as UI features in the GDD (not as items).

| F1.1 name | type | reason |
|---|---|---|
| loader | item | hidden in 1.1 base (editor only); possible later QoL item |
| fast-loader | item | hidden in 1.1 base (editor only); possible later QoL item |
| express-loader | item | hidden in 1.1 base (editor only); possible later QoL item |
| dummy-steel-axe | mining-tool | editor/debug/hidden |
| blueprint | blueprint | blueprint-family tool → UI feature |
| deconstruction-planner | deconstruction-item | blueprint-family tool → UI feature |
| upgrade-planner | upgrade-item | blueprint-family tool → UI feature |
| blueprint-book | blueprint-book | blueprint-family tool → UI feature |
| copy-paste-tool | copy-paste-tool | blueprint-family tool → UI feature |
| cut-paste-tool | copy-paste-tool | blueprint-family tool → UI feature |
| coin | item | editor/debug/hidden |
| tank-machine-gun | gun | vehicle-mounted weapon (internal to vehicle; combat phase) |
| vehicle-machine-gun | gun | vehicle-mounted weapon (internal to vehicle; combat phase) |
| tank-flamethrower | gun | vehicle-mounted weapon (internal to vehicle; combat phase) |
| artillery-wagon-cannon | gun | vehicle-mounted weapon (internal to vehicle; combat phase) |
| spidertron-rocket-launcher-1 | gun | vehicle-mounted weapon (internal to vehicle; combat phase) |
| spidertron-rocket-launcher-2 | gun | vehicle-mounted weapon (internal to vehicle; combat phase) |
| spidertron-rocket-launcher-3 | gun | vehicle-mounted weapon (internal to vehicle; combat phase) |
| spidertron-rocket-launcher-4 | gun | vehicle-mounted weapon (internal to vehicle; combat phase) |
| tank-cannon | gun | vehicle-mounted weapon (internal to vehicle; combat phase) |
| player-port | item | editor/debug/hidden |
| electric-energy-interface | item | editor/debug/hidden |
| linked-chest | item | editor/debug/hidden |
| heat-interface | item | editor/debug/hidden |
| linked-belt | item | editor/debug/hidden |
| infinity-chest | item | editor/debug/hidden |
| infinity-pipe | item | editor/debug/hidden |
| selection-tool | selection-tool | editor/debug/hidden |
| item-with-inventory | item-with-inventory | editor/debug/hidden |
| item-with-label | item-with-label | editor/debug/hidden |
| item-with-tags | item-with-tags | editor/debug/hidden |
| simple-entity-with-force | item | editor/debug/hidden |
| simple-entity-with-owner | item | editor/debug/hidden |
| burner-generator | item | editor/debug/hidden |
| item-unknown | item | editor/debug/hidden |

**Totals:** 200 shippable items (all phases) + 8 fluids; 35 excluded.
