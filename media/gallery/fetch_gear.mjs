// Fetches one character's equipped gear (names in German, quality, item level, enchantments, icons) and its
// rendered picture from the Battle.net profile API, for the character page mock-ups (mock_character.py).
//
//   node --env-file=<file with BATTLENET_CLIENT_ID/SECRET> media/gallery/fetch_gear.mjs <character-slug>
//
// Writes src/gear.json, src/items/<item id>.jpg and src/render.png (src/ is local only).
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const SRC = join(HERE, 'src')
const slug = process.argv[2] ?? 'eoy-goldcog'
const token = await (await fetch('https://oauth.battle.net/token', {
  method: 'POST',
  headers: { Authorization: 'Basic ' + Buffer.from(`${process.env.BATTLENET_CLIENT_ID}:${process.env.BATTLENET_CLIENT_SECRET}`).toString('base64'),
    'Content-Type': 'application/x-www-form-urlencoded' },
  body: 'grant_type=client_credentials',
})).json().then(r => r.access_token)
const get = async url => {
  const r = await fetch(url, { headers: { Authorization: `Bearer ${token}` } })
  if (!r.ok) throw new Error(`HTTP ${r.status} ${url}`)
  return r.json()
}
const base = `https://eu.api.blizzard.com/profile/wow/character/${slug}`
const eq = await get(`${base}/equipment?namespace=profile-forever-eu&locale=de_DE`)
mkdirSync(join(SRC, 'items'), { recursive: true })
const items = []
for (const it of eq.equipped_items ?? []) {
  const media = await get(`${it.media.key.href}&locale=de_DE`)
  const icon = media.assets?.find(a => a.key === 'icon')?.value
  if (icon) writeFileSync(join(SRC, 'items', `${it.item.id}.jpg`), Buffer.from(await (await fetch(icon)).arrayBuffer()))
  items.push({
    slot: it.slot.type, name: it.name, id: it.item.id, quality: it.quality.type, level: it.level?.value,
    enchants: (it.enchantments ?? []).map(e => e.display_string).filter(Boolean),
    stats: (it.stats ?? []).map(s => s.display?.display_string).filter(Boolean),
    armor: it.armor?.display?.display_string ?? null,
  })
}
writeFileSync(join(SRC, 'gear.json'), JSON.stringify(items, null, 1))
const charMedia = await get(`${base}/character-media?namespace=profile-forever-eu`)
const main = charMedia.assets?.find(a => a.key === 'main-raw')?.value
if (main) writeFileSync(join(SRC, 'render.png'), Buffer.from(await (await fetch(main)).arrayBuffer()))
console.log(`${items.length} items, render ${main ? 'saved' : 'missing'}`)
for (const it of items) console.log(`  ${it.slot.padEnd(10)} ${String(it.level).padStart(3)} ${it.quality.padEnd(9)} ${it.name}${it.enchants.length ? '  [' + it.enchants.join('; ') + ']' : ''}`)
