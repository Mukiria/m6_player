// Builds lib/widgets/logo_animation_data.dart from the animated logo SVGs in this folder.
//
//   node branding/make-logo-animation.js
//
// Flutter can't play the SVGs' CSS/SMIL animation, so the app redraws it itself
// (lib/widgets/app_logo.dart). This script extracts what it needs: the wave's
// keyframes, and each logo part (earbuds, "m6", "player") as its own small SVG
// in the same viewBox as the static logo in assets/branding/.
const fs = require('fs');
const path = require('path');

const APP = path.join(__dirname, '..');
const OUT = path.join(APP, 'lib/widgets/logo_animation_data.dart');

// The static, trimmed logo's viewBox, so the parts line up with it exactly.
const staticLogo = fs.readFileSync(path.join(APP, 'assets/branding/logo-light.svg'), 'utf8');
const viewBox = staticLogo.match(/viewBox="([^"]+)"/)[1].split(' ').map(Number);

function parse(theme) {
  const svg = fs.readFileSync(path.join(__dirname, `m6-player-logo-${theme}-animated.svg`), 'utf8')
    .replace(/<metadata>[\s\S]*?<\/metadata>/, '');

  // Wave keyframes: same x for every point, only y changes.
  const values = svg.match(/<animate attributeName="d"[^>]*values="([^"]*)"/)[1]
    .split(';').map((v) => v.trim()).filter(Boolean);
  const frames = values.map((v) => [...v.matchAll(/[ML]\s*([\d.\-]+),([\d.\-]+)/g)].map((m) => [+m[1], +m[2]]));
  const dur = parseFloat(svg.match(/<animate attributeName="d"[^>]*dur="([\d.]+)s"/)[1]);

  const outer = svg.match(/<g transform="translate\(([\d.]+),([\d.]+)\) scale\(([\d.]+)\)">/);
  const stops = [...svg.match(/<linearGradient[\s\S]*?<\/linearGradient>/)[0]
    .matchAll(/offset="([\d.]+)" stop-color="#([0-9a-f]{6})"/g)].map((m) => [+m[1], m[2]]);
  const gradientX = svg.match(/<linearGradient[^>]*x1="([\d.]+)"[^>]*x2="([\d.]+)"/).slice(1, 3).map(Number);
  // The wave is the path holding the <animate>; read its stroke width.
  const wavePath = svg.match(/<path\b[^>]*>\s*<animate attributeName="d"/)[0];
  const strokeWidth = +wavePath.match(/stroke-width="([\d.]+)"/)[1];

  // Parts, with or without the animation classes ("bud left", "word a"...).
  const budLeft = svg.match(/<g transform="translate\(160,120\) scale\(-1,1\)"><g(?: class="[^"]*")?>([\s\S]*?)<\/g><\/g>/)[1];
  const budRight = svg.match(/<g transform="translate\(540,120\)"><g(?: class="[^"]*")?>([\s\S]*?)<\/g><\/g>/)[1];
  // The two words are the last two top-level paths, after the wave group.
  const words = [...svg.slice(svg.lastIndexOf('</g>')).matchAll(/<path (?:class="[^"]*" )?(d="[^"]*"[^>]*)\/>/g)].map((m) => m[1]);
  const [wordA, wordB] = words;

  // Timings from the CSS: [delay s, duration s, x1, y1, x2, y2 of the cubic-bezier],
  // or null for a part that doesn't animate.
  const css = (svg.match(/<style>([\s\S]*?)<\/style>/) || ['', ''])[1];
  const rule = (selector) => {
    const m = css.match(new RegExp(selector.replace(/\./g, '\\.') + '\\s*\\{([^}]*)\\}'));
    return m ? m[1] : '';
  };
  const timing = (cls, sub, keyframes) => {
    const base = rule('.' + cls).match(new RegExp('animation:\\s*' + keyframes + '\\s+([\\d.]+)s(?:\\s+([\\d.]+)s)?\\s+cubic-bezier\\(([^)]*)\\)'));
    if (!base) return null;
    const delayRule = sub ? rule('.' + cls + '.' + sub).match(/animation-delay:\s*([\d.]+)s/) : null;
    const delay = delayRule ? +delayRule[1] : +(base[2] || 0);
    return [delay, +base[1], ...base[3].split(',').map(Number)];
  };
  const timings = {
    cable: timing('cable', null, 'draw'),
    budLeft: timing('bud', 'left', 'pop'),
    budRight: timing('bud', 'right', 'pop'),
    wordA: timing('word', 'a', 'rise'),
    wordB: timing('word', 'b', 'rise'),
  };

  const wrap = (body) =>
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox.join(' ')}">${body}</svg>`;
  const inner = (body) => wrap(`<g transform="translate(${outer[1]},${outer[2]}) scale(${outer[3]})">${body}</g>`);

  return {
    frames, dur, stops, gradientX, strokeWidth, timings,
    outer: outer.slice(1, 4).map(Number),
    parts: {
      budLeft: inner(`<g transform="translate(160,120) scale(-1,1)">${budLeft}</g>`),
      budRight: inner(`<g transform="translate(540,120)">${budRight}</g>`),
      wordA: wrap(`<path ${wordA}/>`),
      wordB: wrap(`<path ${wordB}/>`),
    },
  };
}

const light = parse('light');
const dark = parse('dark');
if (JSON.stringify(light.frames) !== JSON.stringify(dark.frames)) throw new Error('Light and dark waves differ');

const xs = light.frames[0].map((p) => p[0]);
light.frames.forEach((f) => f.forEach((p, i) => { if (p[0] !== xs[i]) throw new Error('Wave x values differ between frames'); }));

if (JSON.stringify(light.timings) !== JSON.stringify(dark.timings)) throw new Error('Light and dark timings differ');

const num = (n) => (Number.isInteger(n) ? n.toFixed(1) : String(n));
const list = (a) => `[${a.map(num).join(', ')}]`;
const str = (s) => `r'''${s}'''`;
const t = (timing) => (timing ? list(timing) : 'null');
const theme = (name, t) => `const LogoTheme ${name} = LogoTheme(
  waveColors: [${t.stops.map((s) => `Color(0xFF${s[1].toUpperCase()})`).join(', ')}],
  waveStops: ${list(t.stops.map((s) => s[0]))},
  budLeft: ${str(t.parts.budLeft)},
  budRight: ${str(t.parts.budRight)},
  wordA: ${str(t.parts.wordA)},
  wordB: ${str(t.parts.wordB)},
);`;

const dart = `// GENERATED by branding/make-logo-animation.js from the animated logo SVGs. Don't edit by hand.
import 'dart:ui';

/// The static logo's viewBox (x, y, width, height); every part below uses it.
const List<double> logoViewBox = ${list(viewBox)};

/// The wave's group transform: translate(x, y) scale(s).
const List<double> logoWaveTransform = ${list(light.outer)};

/// Wave gradient runs from x1 to x2 (in the wave group's coordinates).
const List<double> logoWaveGradientX = ${list(light.gradientX)};
const double logoWaveStrokeWidth = ${num(light.strokeWidth)};

/// When each part animates, from the SVGs' CSS: [delay s, duration s, then the
/// cubic-bezier's x1, y1, x2, y2], or null when that part doesn't animate.
/// The cable draws itself; earbuds pop (scale from 0); words rise and fade in.
const List<double>? logoCableDraw = ${t(light.timings.cable)};
const List<double>? logoBudLeftPop = ${t(light.timings.budLeft)};
const List<double>? logoBudRightPop = ${t(light.timings.budRight)};
const List<double>? logoWordARise = ${t(light.timings.wordA)};
const List<double>? logoWordBRise = ${t(light.timings.wordB)};

/// One wave loop, in seconds; the keyframes are evenly spaced over it.
const double logoWaveSeconds = ${num(light.dur)};

/// x of each wave point, and y per keyframe (the last keyframe equals the first).
const List<double> logoWaveX = ${list(xs)};
const List<List<double>> logoWaveY = [
${light.frames.map((f) => `  ${list(f.map((p) => p[1]))},`).join('\n')}
];

/// Colours and SVG parts of one version of the logo.
class LogoTheme {
  final List<Color> waveColors;
  final List<double> waveStops;
  final String budLeft, budRight, wordA, wordB;

  const LogoTheme({
    required this.waveColors,
    required this.waveStops,
    required this.budLeft,
    required this.budRight,
    required this.wordA,
    required this.wordB,
  });
}

${theme('logoLight', light)}

${theme('logoDark', dark)}
`;

fs.writeFileSync(OUT, dart);
console.log(`wrote ${path.relative(APP, OUT)}: ${light.frames.length} keyframes x ${xs.length} points`);
