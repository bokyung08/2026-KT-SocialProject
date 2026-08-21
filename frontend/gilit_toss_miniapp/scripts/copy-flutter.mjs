import { cpSync, rmSync, existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const flutterBuildDir = path.resolve(root, '../pm_safeline_flutter/build/web');
const distDir = path.resolve(root, 'dist');

if (!existsSync(flutterBuildDir)) {
  console.error(`Flutter web build not found at ${flutterBuildDir}. Run "flutter build web --release" first.`);
  process.exit(1);
}

rmSync(distDir, { recursive: true, force: true });
mkdirSync(distDir, { recursive: true });
cpSync(flutterBuildDir, distDir, { recursive: true });

console.log(`Copied Flutter web build -> ${distDir}`);
