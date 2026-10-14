// Generates the paved road texture: dark asphalt grain with the lane markings painted in.
// The texture covers the full road width across (u) and TEXTURE_LENGTH metres along (v), and tiles along the road.
// Keep ROAD_WIDTH and TEXTURE_LENGTH in step with config.lua (road.width and surfaces[paved].textureLength).
//
// Run: bun tools/make-road-texture.ts

import { deflateSync } from "node:zlib"

const ROAD_WIDTH = 8 // metres
const TEXTURE_LENGTH = 16 // metres along the road
const PIXELS_PER_METRE = 128
const EDGE_LINE_OFFSET = 0.35 // from the road edge to the middle of the edge line
const LINE_WIDTH = 0.15
const DASH_LENGTH = 4 // a quarter of the length: 4 m of paint, 12 m of gap
const SEED = 7

const width = ROAD_WIDTH * PIXELS_PER_METRE
const height = TEXTURE_LENGTH * PIXELS_PER_METRE

const PAINT_WHITE = [236, 236, 226]
const PAINT_YELLOW = [224, 168, 14]

function hash(x: number, y: number, seed: number): number {
  let h = Math.imul(x, 374761393) ^ Math.imul(y, 668265263) ^ Math.imul(seed, 1442695041)
  h = Math.imul(h ^ (h >>> 13), 1274126177)
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296
}

/** Smooth noise that wraps every `cellsX` by `cellsY` lattice cells, so the texture tiles. */
function tilingNoise(x: number, y: number, cellsX: number, cellsY: number, seed: number): number {
  const gx = x * cellsX
  const gy = y * cellsY
  const ix = Math.floor(gx)
  const iy = Math.floor(gy)
  const fx = gx - ix
  const fy = gy - iy
  const ux = fx * fx * (3 - 2 * fx)
  const uy = fy * fy * (3 - 2 * fy)
  const at = (i: number, j: number) => hash(((i % cellsX) + cellsX) % cellsX, ((j % cellsY) + cellsY) % cellsY, seed)
  const top = at(ix, iy) + (at(ix + 1, iy) - at(ix, iy)) * ux
  const bottom = at(ix, iy + 1) + (at(ix + 1, iy + 1) - at(ix, iy + 1)) * ux
  return top + (bottom - top) * uy
}

/** Fraction of the pixel [p, p + 1) that lies inside [from, to). */
function coverage(p: number, from: number, to: number): number {
  return Math.max(0, Math.min(p + 1, to) - Math.max(p, from))
}

function asphalt(px: number, py: number): number {
  const x = px / width
  const y = py / height
  let grain = 0
  let total = 0
  for (const [cell, weight] of [[8, 0.25], [16, 0.4], [32, 0.6], [64, 0.85], [128, 0.95], [256, 0.95]] as const) {
    grain += (tilingNoise(x, y, cell * 4, cell * 4 * (TEXTURE_LENGTH / ROAD_WIDTH), SEED + cell) - 0.5) * weight
    total += weight
  }
  const speckle = hash(px, py, SEED) > 0.975 ? 26 : 0
  return 78 + (grain / total) * 70 + speckle
}

function paintAt(px: number, py: number): { colour: number[]; amount: number } {
  const edge = EDGE_LINE_OFFSET * PIXELS_PER_METRE
  const half = (LINE_WIDTH * PIXELS_PER_METRE) / 2
  const centre = width / 2
  const edgeCoverage = Math.max(
    coverage(px, edge - half, edge + half),
    coverage(px, width - edge - half, width - edge + half),
  )
  const dashLength = DASH_LENGTH * PIXELS_PER_METRE
  const centreCoverage = coverage(px, centre - half, centre + half) * coverage(py, 0, dashLength)
  // worn paint: the asphalt grain shows through in patches
  const wear = 0.82 + 0.18 * tilingNoise(px / width, py / height, 24, 96, SEED + 99)
  if (centreCoverage > edgeCoverage) return { colour: PAINT_YELLOW, amount: centreCoverage * wear }
  return { colour: PAINT_WHITE, amount: edgeCoverage * wear }
}

const pixels = new Uint8Array(width * height * 3)
for (let py = 0; py < height; py++) {
  for (let px = 0; px < width; px++) {
    const base = asphalt(px, py)
    const { colour, amount } = paintAt(px, py)
    const o = (py * width + px) * 3
    pixels[o] = base + (colour[0] * (0.78 + base / 400) - base) * amount
    pixels[o + 1] = base * 0.99 + (colour[1] * (0.78 + base / 400) - base * 0.99) * amount
    pixels[o + 2] = base * 0.97 + (colour[2] * (0.78 + base / 400) - base * 0.97) * amount
  }
}

const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
  return c >>> 0
})

function crc32(bytes: Uint8Array): number {
  let c = 0xffffffff
  for (const b of bytes) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}

function chunk(type: string, data: Uint8Array): Uint8Array {
  const out = new Uint8Array(12 + data.length)
  const view = new DataView(out.buffer)
  view.setUint32(0, data.length)
  out.set(new TextEncoder().encode(type), 4)
  out.set(data, 8)
  view.setUint32(8 + data.length, crc32(out.subarray(4, 8 + data.length)))
  return out
}

function encodePng(): Uint8Array {
  const header = new Uint8Array(13)
  const view = new DataView(header.buffer)
  view.setUint32(0, width)
  view.setUint32(4, height)
  header.set([8, 2, 0, 0, 0], 8) // 8-bit RGB
  const rows = new Uint8Array((width * 3 + 1) * height)
  for (let y = 0; y < height; y++) rows.set(pixels.subarray(y * width * 3, (y + 1) * width * 3), y * (width * 3 + 1) + 1)
  const parts = [
    new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(rows, { level: 9 })),
    chunk("IEND", new Uint8Array(0)),
  ]
  const png = new Uint8Array(parts.reduce((n, p) => n + p.length, 0))
  let offset = 0
  for (const p of parts) {
    png.set(p, offset)
    offset += p.length
  }
  return png
}

const target = new URL("../mod/art/aLongDrive/road_paved.png", import.meta.url).pathname
await Bun.write(target, encodePng())
console.log(`wrote ${target} (${width}x${height})`)
