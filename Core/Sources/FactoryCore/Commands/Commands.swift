// Gearforge — FactoryCore
// Every player action goes through `World.execute(_:)`. Validation (reach, inventory, placement rules, fast-replace),
// item accounting and undo records live here. Owner: Gameplay engineer. STUB — keep case names stable (UI uses them).

public enum PlacementError: Error, Equatable, Sendable {
    case outOfBounds, blocked, water, needsShoreline, noResourceUnderDrill, outOfReach, notInInventory
    case wouldMixFluids, notResearched, invalidTile, cannotRotate, nothingThere, inventoryFull, notAllowed
    case custom(String)
}

public enum PlayerCommand: Sendable {
    // Building
    case build(item: Int, origin: TilePos, direction: Direction)
    case buildGhost(entityProto: Int, origin: TilePos, direction: Direction)
    case placeTiles(item: Int, tiles: [TilePos])
    case remove(entity: Int32)
    case removeArea(TileRect, kinds: Set<EntityKind>?)
    case rotate(entity: Int32, clockwise: Bool)
    // Machine configuration
    case setRecipe(entity: Int32, recipe: Int)
    case insertModule(entity: Int32, item: Int)
    case removeModule(entity: Int32, slot: Int)
    case setInserterFilter(entity: Int32, slot: Int, item: Int)
    case setSplitter(entity: Int32, settings: SplitterSettings)
    case setChestBar(entity: Int32, bar: Int?)
    case pasteSettings(from: Int32, to: Int32)
    case launchRocket(entity: Int32)
    // Item transfer between player and an entity
    case transferToEntity(entity: Int32, item: Int, count: Int)
    case transferFromEntity(entity: Int32, item: Int, count: Int)
    case takeAll(entity: Int32)
    case pickUpBeltItems(entity: Int32)
    // Character
    case craft(recipe: Int, count: Int)
    case cancelCraft(queueIndex: Int)
    case startMining(TilePos)
    case stopMining
    case sortInventory
    // Research
    case setResearch(tech: Int)
    case enqueueResearch(tech: Int)
    case dequeueResearch(tech: Int)
}

public enum CommandResult: Equatable, Sendable {
    case ok
    case failed(PlacementError)
    public var isOK: Bool { if case .ok = self { return true }; return false }
}

public extension World {
    /// Validates placing entity prototype `proto` at `origin`. nil = OK. Does not check reach/inventory.
    func canPlace(proto: Int, origin: TilePos, direction: Direction) -> PlacementError? {
        let (w, h) = footprint(proto, direction)
        let rect = TileRect(origin: origin, w: w, h: h)
        var err: PlacementError?
        rect.forEach { p in
            if err != nil { return }
            if !surface.isInBounds(p) { err = .outOfBounds; return }
            if surface.occupant(at: p) >= 0 { err = .blocked; return }
            let t = surface.tile(at: p)
            if t >= 0 && db.tiles[t].isWater { err = .water }
        }
        return err
    }

    /// Executes a player command. STUB: Gameplay engineer implements every case.
    func execute(_ cmd: PlayerCommand) -> CommandResult { .failed(.notAllowed) }
}
