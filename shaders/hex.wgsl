// keep this in sync with your logic manually!!!
const CHUNK_SIZE : u32 = 32;
const CHUNK_SIZE_I : i32 = i32(CHUNK_SIZE);
const CHUNK_SIZE_PADDED : u32 = CHUNK_SIZE+2;
const ARRAY_LEN : u32 = (CHUNK_SIZE_PADDED*CHUNK_SIZE_PADDED)/2;
// completely retarded: wgpu forces alignment 16 on arrays in uniform buffers, so we need to store our 8 byte tiles grouped as vec4<u32>
// the data contains pairs of these packed tiles that are unpacked in the vertex shader:
// struct PackedTile { 
//     old_and_new_ter: u32,  // 2xu16 
//     new_fact_and_vis: u32, // 2xf16
// }
struct HexChunkData {
    chunk_pos: IVec2,
    // we should have some padding here, such that the tiles start at align 16
    // is actually array<vec2<PackedTile>> representing array<PackedTile> for 16 alignment
    tiles: array<vec4<u32>, ARRAY_LEN>, 
}
@group(3) @binding(0) var<uniform> hex_chunk_terrain : HexChunkData;

struct Tile {
    old_ter:  u32,
    new_ter:  u32,
    new_fact_and_vis: Vec2, 
}
fn get_data(idx_in_chunk: u32) -> Tile {
    let buf_idx = idx_in_chunk / 2;
    let comp_idx = (idx_in_chunk % 2) * 2; // 0 or 2
    let two_tiles: vec4<u32> = hex_chunk_terrain.tiles[buf_idx];

    var res: Tile;
    let u8_values = unpack4xU8(two_tiles[comp_idx]);
    res.old_ter = u8_values[0];
    res.new_ter = u8_values[1];
    let old_vis_255 = f32(u8_values[2]);
    let new_vis_255 = f32(u8_values[3]);
    
    let new_fact = bitcast<f32>(two_tiles[comp_idx + 1]);
    // let new_fact = frame.xxx.x;
    let vis = (old_vis_255 + ((new_vis_255 - old_vis_255) * new_fact)) * (1.0 / 255.0);
    res.new_fact_and_vis = Vec2(new_fact, vis);
    return res;
}

fn get_visibility(idx_in_chunk: u32) -> f32 {
    let buf_idx = idx_in_chunk / 2;
    let comp_idx = (idx_in_chunk % 2) * 2; // 0 or 2
    let two_tiles: vec4<u32> = hex_chunk_terrain.tiles[buf_idx];

    
    let u8_values = unpack4xU8(two_tiles[comp_idx]);
    let old_vis_255 = f32(u8_values[2]);
    let new_vis_255 = f32(u8_values[3]);

    let new_fact = bitcast<f32>(two_tiles[comp_idx + 1]);
    // let new_fact = frame.xxx.x;
    let vis = (old_vis_255 + ((new_vis_255 - old_vis_255) * new_fact)) * (1.0 / 255.0);
    return vis;
}

const HEX_TO_WORLD_POS_MAT : mat2x2f = mat2x2f(1.5,  -0.75, 0, 1.5);
const WORLD_TO_HEX_POS_MAT : mat2x2f = mat2x2f(2.0 / 3.0, 1.0 / 3.0, 0.0, 2.0 / 3.0);
fn hex_to_world_pos(hex_pos: IVec2) -> Vec2 {
    return HEX_TO_WORLD_POS_MAT * Vec2(f32(hex_pos.x), f32(hex_pos.y));
}
fn world_to_hex_pos(world_pos: Vec2) -> Vec2 {
    return WORLD_TO_HEX_POS_MAT * world_pos;
}