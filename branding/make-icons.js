// Builds m6 player's in-app logos and launcher icons from the brand SVGs in this folder.
//
//   cd branding && npm install --no-save @resvg/resvg-js pngjs && node make-icons.js
//
// Writes: assets/branding/logo-{light,dark}.svg (trimmed, no background), the Android
// launcher and adaptive icons, the iOS app icons (no alpha), and play-store-icon-512.png.
const fs = require('fs');
const path = require('path');
const { Resvg } = require('@resvg/resvg-js');
const { PNG } = require('pngjs');

const SRC = __dirname;
const APP = path.join(__dirname, '..');
const PREVIEW = path.join(require('os').tmpdir(), 'm6player-icon-preview');
fs.mkdirSync(PREVIEW, { recursive: true });

const read = (f) => fs.readFileSync(path.join(SRC, f), 'utf8')
  .replace(/<metadata>[\s\S]*?<\/metadata>/, '')
  .replace(/\s*xmlns:c2pa="[^"]*"/, '');

function render(svg, size, { opaque = false } = {}) {
  const png = new Resvg(svg, { fitTo: { mode: 'width', value: size } }).render().asPng();
  if (!opaque) return png;
  // iOS and the Play Store reject icons with an alpha channel: write plain RGB.
  const img = PNG.sync.read(png);
  return PNG.sync.write(img, { colorType: 2 });
}

function write(file, buf) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, buf);
}

// --- In-app logos: drop the background rect and crop the viewBox to the artwork.
function trimmedLogo(file) {
  let svg = read(file).replace(/\s*<rect width="1200" height="630"[^>]*\/>/, '');
  const box = new Resvg(svg).innerBBox(); // bounding box of what is actually drawn
  const pad = 8;
  const x = Math.floor(box.x - pad), y = Math.floor(box.y - pad);
  const w = Math.ceil(box.width + 2 * pad), h = Math.ceil(box.height + 2 * pad);
  svg = svg.replace(/viewBox="[^"]*" width="1200" height="630"/,
    `viewBox="${x} ${y} ${w} ${h}" width="${w}" height="${h}"`);
  return svg;
}

const light = trimmedLogo('m6-player-logo-light.svg');
const dark = trimmedLogo('m6-player-logo-dark.svg');
write(path.join(APP, 'assets/branding/logo-light.svg'), light);
write(path.join(APP, 'assets/branding/logo-dark.svg'), dark);
write(path.join(PREVIEW, 'logo-light.png'), render(light, 600));
write(path.join(PREVIEW, 'logo-dark.png'), render(dark, 600));

// --- Icons.
const square = read('m6-player-app-icon-square.svg');
const BG = '#0b1533';

// Adaptive-icon foreground: the artwork without its background, shrunk into the
// centre safe zone (Android masks the outer third of the 108dp layer).
const artwork = square.replace(/\s*<rect width="1024" height="1024"[^>]*\/>/, '');
const artBox = new Resvg(artwork).innerBBox();
const cx = artBox.x + artBox.width / 2, cy = artBox.y + artBox.height / 2;
const safeDiameter = 1024 * 64 / 108;           // keep inside the 66dp circle, with margin
const scale = safeDiameter / Math.hypot(artBox.width, artBox.height);
const foreground = artwork
  .replace(/(<svg[^>]*>)/, `$1<g transform="translate(512 512) scale(${scale.toFixed(4)}) translate(${-cx} ${-cy})">`)
  .replace(/<\/svg>\s*$/, '</g></svg>');

const android = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
for (const [dpi, k] of Object.entries(android)) {
  const dir = path.join(APP, `android/app/src/main/res/mipmap-${dpi}`);
  write(path.join(dir, 'ic_launcher.png'), render(square, 48 * k));
  write(path.join(dir, 'ic_launcher_foreground.png'), render(foreground, 108 * k));
}
write(path.join(APP, 'android/app/src/main/res/values/ic_launcher_background.xml'),
  `<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">${BG.toUpperCase()}</color>\n</resources>\n`);

const iosDir = path.join(APP, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
const contents = JSON.parse(fs.readFileSync(path.join(iosDir, 'Contents.json'), 'utf8'));
for (const img of contents.images) {
  const px = Math.round(parseFloat(img.size) * parseInt(img.scale));
  write(path.join(iosDir, img.filename), render(square, px, { opaque: true }));
}

// Play Store listing icon (512 x 512, no alpha) and previews.
write(path.join(APP, 'branding/play-store-icon-512.png'), render(square, 512, { opaque: true }));
write(path.join(PREVIEW, 'icon.png'), render(square, 300));
// Preview of the foreground on its background, with the circle mask Android may apply.
const maskPreview = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><defs><clipPath id="c"><circle cx="512" cy="512" r="${1024 * 36 / 108}"/></clipPath></defs><g clip-path="url(#c)"><rect width="1024" height="1024" fill="${BG}"/>${foreground.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '')}</g></svg>`;
write(path.join(PREVIEW, 'adaptive-circle.png'), render(maskPreview, 300));
console.log('done; foreground scale', scale.toFixed(3), 'logo boxes ok');
