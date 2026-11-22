import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ACHIEVEMENT_DEFINITIONS } from '../src/achievements/definitions.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const rootDir = path.resolve(__dirname, '../..');
const appAssetsDir = path.resolve(rootDir, 'app/assets/achievements');

if (!fs.existsSync(appAssetsDir)) {
  fs.mkdirSync(appAssetsDir, { recursive: true });
}

const payload = [...ACHIEVEMENT_DEFINITIONS].sort((a, b) => a.order - b.order);

const outputPath = path.join(appAssetsDir, 'achievements.json');
fs.writeFileSync(outputPath, JSON.stringify(payload, null, 2) + '\n', 'utf8');

console.log(`✓ achievements.json exported to: ${outputPath}`);
console.log(`  - total achievements: ${payload.length}`);
