# Localization (English + Russian)

Owner: localization. Tooling: `tools/l10n/`. Runtime: `App/Sources/App/Localization.swift`.

## How it works

Two string tables per language, under `App/Resources/<lang>.lproj/`:

| Table | Key | Looked up by |
|---|---|---|
| `Localizable.strings` | the exact English text (`"Out of %@"`) | SwiftUI `Text("…")`, `Button("…")`, `Toggle`, `Picker`, `TextField`, `Stepper`, `.alert`, `.confirmationDialog`; `L("…")` / `LF("… %@", args)`; `show("…")` toasts; helpers that pass their title through `LocalizedStringKey`/`L` (`MenuButton(title:subtitle:)`, `PanelChrome(title:)`, `row`, `itemsRow`, `prioPicker`, `column`, `LoadingView(text:)`, `start(label:)`); Core strings shown via `L()` (`PlacementError.message`, `.custom("…")`, `.alert("…")`, `EntityStatus.label`) |
| `GameData.strings` | `item.<id>`, `entity.<id>`, `recipe.<id>`, `tech.<id>`, `fluid.<id>`, `group.<id>`, `tile.<id>`, `resource.<id>`, `level.<L>.title/subtitle/teaches`, `objective.<L>.<n>.title/hint` | `Names.*` (`db.itemName(i)` etc.); missing keys fall back to the English name in `GameData.json` / `Levels.swift` |

All four `.strings` files are **generated** — never edit them by hand.

```
tools/l10n/extract.py   scans the sources -> {"ui": [english…], "data": {key: english}}
tools/l10n/ru.json      hand-written Russian: {"ui": {english: russian}, "data": {key: russian}}
tools/l10n/build.py     extract + ru.json -> App/Resources/{en,ru}.lproj/{Localizable,GameData}.strings
```

`extract.py` lexes every Swift file in `App/Sources` (comments, escapes and `\( )` interpolation aware) and keeps a
literal only when it is the key argument of one of the calls above (first unlabelled argument, or the `title:` /
`subtitle:` / `text:` / `label:` label of the helper; ternaries of literals count). It skips literals without letters,
asset names (`ui_`, `i_`, `e_`, …), ids, file names and SF Symbols. Core: the `message`/`label` switches,
`.custom("…")`, `.alert("…")`. Data: `GameData.json` arrays and the 8 `LevelDefinition`s / `o(n, "title", .kind(…),
"hint")` calls in `Levels.swift`. Output is sorted and deterministic.

`build.py` writes the files (UTF-8, `"key" = "value";`, sorted, `\\ \" \n` escaped), re-parses every file it wrote
(round trip), checks that English and Russian use the same format specifiers in the same order (`%@`, `%%`, `%lld`),
reports missing Russian keys and stale `ru.json` keys. `--strict` exits 1 on any missing key or error; `--check`
validates without writing.

```
python3 tools/l10n/extract.py --report   # counts + "needs code change" list
python3 tools/l10n/build.py --strict     # regenerate tables; must print OK
```

## Adding or changing a string

1. Write the code with the English text as the key:
   * SwiftUI literal: `Text("Take all")`, `Button("Sort")` — nothing else needed.
   * `String` paths: `L("No recipe")`; with values: `LF("Researching %@", name)` — **only `%@` and `%%`** in LF keys;
     convert numbers to strings at the call site (`"\(n)"`). Never `Text("Out of \(x)")` or `String(format:)` with words.
   * Game content: add it to `GameData.json` / `Levels.swift`; keys are derived from the ids.
2. Run `python3 tools/l10n/build.py` — it lists the new keys under "Missing Russian".
3. Add the translations to `tools/l10n/ru.json` (`ui` for UI keys, `data` for content keys). Keep `%@`/`%%` exactly.
4. Run `python3 tools/l10n/build.py --strict` until it prints `OK`, commit `ru.json` **and** the four `.strings` files.
   Stale keys (text removed from the code) are reported; delete them from `ru.json`.

New Swift helpers that take a title and localise it internally must be added to `UI_CALLS` in `extract.py`.

## Style (Russian)

* Short, neutral game-UI Russian; buttons are verbs in infinitive/imperative ("Сохранить", "Забрать всё"),
  statuses are short states ("Нет топлива", "Ждёт ингредиентов"), hints address the player as «вы» politely
  ("Поставьте бур…").
* Objectives: infinitive ("Построить 8 маяков", "Исследовать «Логистику»") with correct number agreement; technology
  names in «ёлочках».
* Values with `%@` go after a colon to avoid case/plural agreement: "Закончилось: %@", "Запущено ракет: %@".
* Use **ё** (Factorio-RU convention). Units: мин, ч, кВт, МВт.
* Tiers keep the number: "Сборочный автомат 2", "Модуль скорости 3", "Автоматизация 2"; MK2 → МК2.

## Glossary

| English | Russian |
|---|---|
| data card / Mechanics card / Motion / Reaction / Defense / Fabrication / Systems / Orbital | карта данных / карта механики (красная) / движения (зелёная) / реакций (синяя) / обороны (чёрная) / фабрикации (фиолетовая) / систем (жёлтая) / орбитальная карта (белая) |
| transport belt / fast / express | транспортный конвейер / скоростной конвейер / экспресс-конвейер |
| underground belt / splitter / lane / sideloading / main bus | подземный конвейер / разделитель / полоса / боковая загрузка / главная шина |
| inserter (burner / fast / long-handed / filter / stack) | манипулятор (твердотопливный / быстрый / длинный / фильтрующий / пакетный) |
| hand size (inserter) | размер захвата |
| burner / electric mining drill | твердотопливный бур / электрический бур |
| stone / steel / electric furnace | каменная / стальная / электрическая печь |
| assembling machine (assembler) | сборочный автомат |
| chemical plant / oil refinery / pumpjack | химзавод / нефтеперерабатывающий завод / станок-качалка |
| beacon / module (speed, efficiency, productivity) | маяк / модуль (скорости, эффективности, продуктивности) |
| lab / research / technology | лаборатория / исследование / технология |
| offshore pump / boiler / steam engine / pump / storage tank | прибрежный насос / бойлер / паровой двигатель / помпа / резервуар |
| small / medium / big electric pole, substation | малая / средняя / большая опора ЛЭП, подстанция |
| electric network / power | электросеть / энергия |
| accumulator / solar panel | аккумулятор / солнечная панель |
| electronic / advanced circuit, processing unit | электронная схема / продвинутая схема, процессор |
| engine unit / electric engine unit | двигатель / электродвигатель |
| low density structure / rocket control unit / flying robot frame | малоплотная конструкция / блок управления ракетой / каркас летающего робота |
| rocket silo / rocket part / satellite / launch | ракетная шахта / часть ракеты / спутник / пуск, запуск |
| crude / heavy / light oil, petroleum gas, lubricant | нефть / тяжёлая / лёгкая нефть, нефтяной газ, смазка |
| plate / ore / gear wheel / copper cable | плита / руда / шестерня / медный провод |
| chest (wooden / iron / steel) | сундук (деревянный / железный / стальной) |
| ghost / reach | призрак / досягаемость |
| craft / crafting | создать / создание |
| hand-mine | добыть вручную |
| freeplay / campaign / level / objective | свободная игра / кампания / уровень / цель |
| autosave / save / load | автосохранение / сохранение / загрузка |
| Par / Best (level times) | норматив / рекорд |

Campaign: L1 «Высадка», L2 «Первый свет», L3 «Сборочная линия», L4 «Движение», L5 «Чёрное золото»,
L6 «Перегонка», L7 «Промышленный размах», L8 «Обратный отсчёт».

## Coverage

| Table | Keys | Russian |
|---|---|---|
| Localizable (UI) | 186 | 186 (100 %) |
| GameData | 817 (item 200, entity 92, recipe 208, tech 192, fluid 8, group 4, tile 13, resource 6, level 24, objective 70) | 817 (100 %) |
| **Total** | **1003** | **1003 (100 %)** |

## Needs code change

These strings reach the player but cannot be translated as written (the tables cannot fix them). Owners of the files
should convert them; `python3 tools/l10n/extract.py --report` re-lists the detectable ones.

| Where | Text | Fix |
|---|---|---|
| App/Sources/App/AppModel.swift:60 | `start(label: "Landing on \(level.title)…")` | `LF("Landing on %@…", Names.levelTitle(level))` (also uses the untranslated title) |
| App/Sources/UI/EntityPanel.swift:106 | `String(format: "Speed %.2f", …)` | `LF("Speed %@", String(format: "%.2f", …))` |
| App/Sources/UI/EntityPanel.swift:171 | `Stepper("Limit: \(inv.bar… ?? "none")")` | works today via SwiftUI key `Limit: %@`, but `"none"` stays English → `LF("Limit: %@", bar ?? L("none"))` |
| App/Sources/UI/EntityPanel.swift:206 | `String(format: "Charge: %.1f / 5 MJ", …)` | `LF("Charge: %@ / 5 MJ", …)` |
| App/Sources/UI/EntityPanel.swift:264 | `String(format: "Accumulators %.0f%%", …)` | `LF("Accumulators %@%%", …)` |
| App/Sources/UI/InventoryPanel.swift:143, OtherPanels.swift:86 | `String(format: "%.1f s" / "%.0f s", …)` | `LF("%@ s", …)` (RU «с») |
| App/Sources/UI/InventoryPanel.swift:155 | `Button("Max (\(n))")` | works today via SwiftUI key `Max (%lld)`; prefer `LF("Max (%@)", "\(n)")` |
| App/Sources/UI/MenuViews.swift:242 | `Stepper("Autosave slots: \(…)")` | works today via SwiftUI key `Autosave slots: %lld`; prefer LF |
| App/Sources/UI/OtherPanels.swift:164 | `String(format: "%.1f / min", …)` | `LF("%@ / min", …)` |
| App/Sources/UI/Theme.swift:47 | `"\(c / 1000)k"` (stack counts) | optional: `LF("%@k", …)` |
| App/Sources/UI/Theme.swift:184-187 | `formatWatts`: `"%.1f GW"`, `"MW"`, `"kW"`, `"W"` | `LF("%@ MW", …)` etc. (RU ГВт/МВт/кВт/Вт) |
| App/Sources/UI/MenuViews.swift:35 | `formatPlayTime`: `"\(h) h \(m) min"`, `"\(m) min"` | `LF("%@ h %@ min", …)`, `LF("%@ min", …)` |
| App/Sources/UI/MenuViews.swift:216-224 | `describe(_:)` builds `"Freeplay"`, `"Campaign · …"`, `" · autosave"` and is shown with `Text(String)` (not looked up) | `L("Freeplay")`, `LF("Campaign · %@", …)`, `L("autosave")` |
| App/Sources/UI/MenuViews.swift:274 | `section(_:)` renders `Text(title.uppercased())` — String, not looked up ("Gameplay", "Interface", "Graphics & performance", "Audio") | `Text(L(title).uppercased())` (keys already translated) |
| App/Sources/UI/OtherPanels.swift:151 | `Text(w.label)` — StatsWindow "1m/10m/1h/10h" shown verbatim | `Text(L(w.label))` (keys already translated) |
| App/Sources/UI/OtherPanels.swift:223, App/Sources/App/AppModel.swift:103, Bridge/GameController.swift:430 | save display names `"Quicksave"`, `"Last exit"`, `"Last session"` are stored in the save and shown verbatim | localise at display time, or store `L(...)` when saving |
| Core/Sources/FactoryCore/World/GroundItems.swift:74 | `.alert("\(lost) items lost — no room on the ground")` | emit a fixed key and count, e.g. `.alert("Items lost — no room on the ground: %@")` + LF in the controller |
| App/Sources/UI/OtherPanels.swift:132 (`effectText` default) | `e.type.replacingOccurrences(of: "-", with: " ")` for unknown effect types | add explicit LF cases when new effect types ship |
