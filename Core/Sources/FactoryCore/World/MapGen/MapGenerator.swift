// Gearforge — FactoryCore
// Deterministic chunk generation: terrain, water, resource patches (guaranteed starting area), trees, rocks.
// Owner: Gameplay engineer. STUB: flat grass.

public final class MapGenerator {
    public unowned let world: World
    public init(world: World) { self.world = world }

    public func generateChunk(_ c: ChunkPos) -> Chunk {
        let grass = max(0, world.db.tile("grass_1"))
        let ch = Chunk(pos: c, fillTile: UInt8(grass))
        return ch
    }
}
