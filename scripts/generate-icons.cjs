#!/usr/bin/env node
'use strict';

// Optional artwork tooling only; Xcode builds use the checked-in PNGs.
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');

const root = path.resolve(__dirname, '..');
const assets = path.join(root, 'TraccarClient/Resources/Assets.xcassets');
const info = { author: 'xcode', version: 1 };

async function writeJSON(file, value) {
    await fs.writeFile(file, `${JSON.stringify(value, null, 2)}\n`);
}

async function render(svg, size, destination) {
    // Rasterize the vector at each output size, without enlarging a raster master.
    const input = svg.replace(/<svg\b[^>]*>/, (tag) => tag
        .replace(/\bwidth="[^"]*"/, `width="${size}px"`)
        .replace(/\bheight="[^"]*"/, `height="${size}px"`));
    await sharp(Buffer.from(input)).ensureAlpha().png().toFile(destination);
}

async function main() {
    const svg = await fs.readFile(path.join(root, 'Artwork/AppIcon.svg'), 'utf8');
    const appIcon = path.join(assets, 'AppIcon.appiconset');
    const menuIcon = path.join(assets, 'MenuBarIcon.imageset');
    await fs.mkdir(appIcon, { recursive: true });
    await fs.mkdir(menuIcon, { recursive: true });
    await writeJSON(path.join(assets, 'Contents.json'), { info });

    const images = [];
    for (const size of [16, 32, 128, 256, 512]) {
        for (const scale of [1, 2]) {
            const filename = `icon_${size}x${size}${scale === 2 ? '@2x' : ''}.png`;
            await render(svg, size * scale, path.join(appIcon, filename));
            images.push({ filename, idiom: 'mac', size: `${size}x${size}`, scale: `${scale}x` });
        }
    }
    await writeJSON(path.join(appIcon, 'Contents.json'), { images, info });

    const menuImages = [];
    const templateSVG = svg.replaceAll('#2d7930', '#000000');
    for (const scale of [1, 2]) {
        const filename = `menu${scale === 2 ? '@2x' : ''}.png`;
        await render(templateSVG, 18 * scale, path.join(menuIcon, filename));
        menuImages.push({ filename, idiom: 'mac', scale: `${scale}x` });
    }
    await writeJSON(path.join(menuIcon, 'Contents.json'), {
        images: menuImages,
        info,
        properties: { 'template-rendering-intent': 'template' },
    });
    console.log(`Generated 10 app icon slots and 2 menu images with sharp ${sharp.versions.sharp}.`);
}

main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
});
