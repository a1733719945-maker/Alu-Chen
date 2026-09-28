import React from 'react';
import {Easing, interpolate, useCurrentFrame} from 'remotion';

// 苍墟 · 猎灵 过场动画的公用零件（全部自己画：SVG 渐变、模糊、粒子、视差，没有外部素材）
export const W = 1280;
export const H = 720;
export const FPS = 30;
export const clamp = {extrapolateLeft: 'clamp' as const, extrapolateRight: 'clamp' as const};
export const SERIF = "'Noto Serif SC', 'Noto Serif SC VF', STSong, SimSun, serif";
export const SANS = "'Noto Sans SC', 'Noto Sans SC VF', 'Microsoft YaHei', sans-serif";
export const GOLD = '#f2cf7a';
export const INK = '#070a12';

export const easeOut = Easing.bezier(0.16, 1, 0.3, 1);
export const easeInOut = Easing.bezier(0.65, 0, 0.35, 1);

// 固定种子的伪随机：同一个 i 每帧都一样
export const rnd = (i: number) => {
	const s = Math.sin(i * 127.1 + 311.7) * 43758.5453;
	return s - Math.floor(s);
};

// 一段时间窗 [a, b] 里的不透明度（淡入 fi 帧、淡出 fo 帧）
export const win = (f: number, a: number, b: number, fi = 12, fo = 12) =>
	Math.min(interpolate(f, [a, a + fi], [0, 1], clamp), interpolate(f, [b - fo, b], [1, 0], clamp));

// SVG 公用滤镜：模糊几档、发光、颗粒
export const Defs: React.FC = () => (
	<defs>
		{[1, 2, 4, 6, 10, 16, 26, 40].map((b) => (
			<filter key={b} id={`b${b}`} x="-50%" y="-50%" width="200%" height="200%">
				<feGaussianBlur stdDeviation={b} />
			</filter>
		))}
		<filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
			<feGaussianBlur stdDeviation="6" result="g" />
			<feMerge>
				<feMergeNode in="g" />
				<feMergeNode in="g" />
				<feMergeNode in="SourceGraphic" />
			</feMerge>
		</filter>
		<filter id="glowBig" x="-80%" y="-80%" width="260%" height="260%">
			<feGaussianBlur stdDeviation="16" result="g" />
			<feMerge>
				<feMergeNode in="g" />
				<feMergeNode in="g" />
				<feMergeNode in="SourceGraphic" />
			</feMerge>
		</filter>
	</defs>
);

// 电影感：颗粒（每帧换种子）、暗角、上下黑边
export const Grain: React.FC<{amount?: number}> = ({amount = 0.07}) => {
	const f = useCurrentFrame();
	return (
		<svg width={W} height={H} style={{position: 'absolute', inset: 0, mixBlendMode: 'overlay', opacity: amount}}>
			<filter id={`grain${f % 8}`}>
				<feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed={f % 8} stitchTiles="stitch" />
				<feColorMatrix type="saturate" values="0" />
			</filter>
			<rect width={W} height={H} filter={`url(#grain${f % 8})`} />
		</svg>
	);
};

export const Vignette: React.FC<{strength?: number}> = ({strength = 0.75}) => (
	<div
		style={{
			position: 'absolute',
			inset: 0,
			background: `radial-gradient(ellipse at center, rgba(0,0,0,0) 45%, rgba(0,0,0,${strength}) 100%)`,
		}}
	/>
);

export const Letterbox: React.FC<{h?: number}> = ({h = 56}) => (
	<>
		<div style={{position: 'absolute', left: 0, right: 0, top: 0, height: h, background: '#000'}} />
		<div style={{position: 'absolute', left: 0, right: 0, bottom: 0, height: h, background: '#000'}} />
	</>
);

// 整体压暗 / 闪白
export const Fade: React.FC<{color?: string; opacity: number}> = ({color = '#000', opacity}) =>
	opacity <= 0.001 ? null : <div style={{position: 'absolute', inset: 0, background: color, opacity}} />;

// 星空：会闪的星星（大的带十字星芒）
export const Stars: React.FC<{n: number; seed: number; alpha?: number; drift?: number; h?: number}> = ({n, seed, alpha = 1, drift = 0, h = H}) => {
	const f = useCurrentFrame();
	return (
		<g opacity={alpha}>
			{Array.from({length: n}).map((_, i) => {
				const x = (rnd(seed + i) * (W + 200) - 100 + drift * f * (0.2 + rnd(seed + i + 3) * 0.8)) % (W + 200);
				const y = rnd(seed + i * 7.3) * h;
				const big = rnd(seed + i * 3.1) > 0.94;
				const tw = 0.55 + 0.45 * Math.sin(f * (0.05 + rnd(seed + i) * 0.12) + i);
				const r = big ? 1.8 : 0.6 + rnd(seed + i * 1.7) * 0.9;
				return (
					<g key={i} opacity={tw}>
						<circle cx={x} cy={y} r={r} fill="#fff" />
						{big && (
							<>
								<rect x={x - 9} y={y - 0.4} width={18} height={0.8} fill="#cfe2ff" opacity={0.7} />
								<rect x={x - 0.4} y={y - 9} width={0.8} height={18} fill="#cfe2ff" opacity={0.7} />
								<circle cx={x} cy={y} r={5} fill="#9cc2ff" opacity={0.25} filter="url(#b4)" />
							</>
						)}
					</g>
				);
			})}
		</g>
	);
};

// 飘着的光点（往上升、左右飘）
export const Motes: React.FC<{n: number; seed: number; color: string; y0?: number; y1?: number; speed?: number; size?: number; alpha?: number}> = ({
	n,
	seed,
	color,
	y0 = 0,
	y1 = H,
	speed = 0.6,
	size = 3,
	alpha = 1,
}) => {
	const f = useCurrentFrame();
	const span = y1 - y0;
	return (
		<g opacity={alpha}>
			{Array.from({length: n}).map((_, i) => {
				const x = rnd(seed + i) * W + Math.sin(f * 0.02 + i) * 18;
				const y = y1 - ((rnd(seed + i * 5.1) * span + f * speed * (0.5 + rnd(seed + i * 2.3))) % span);
				const r = size * (0.4 + rnd(seed + i * 9.7));
				const a = 0.35 + 0.65 * Math.abs(Math.sin(f * 0.04 + i * 1.3));
				return <circle key={i} cx={x} cy={y} r={r} fill={color} opacity={a} filter="url(#b2)" />;
			})}
		</g>
	);
};

// 云海：几层模糊的椭圆，慢慢往一边流（parallax 越大越近）
export const CloudSea: React.FC<{y: number; color: string; light: string; layers?: number; speed?: number; seed?: number}> = ({
	y,
	color,
	light,
	layers = 4,
	speed = 1,
	seed = 3,
}) => {
	const f = useCurrentFrame();
	return (
		<g>
			{Array.from({length: layers}).map((_, L) => {
				const k = (L + 1) / layers;
				const yy = y + L * 38;
				const n = 9 + L * 2;
				return (
					<g key={L} filter={`url(#b${[16, 10, 10, 6][L % 4]})`} opacity={0.55 + k * 0.4}>
						<rect x={-50} y={yy + 20} width={W + 100} height={H - yy} fill={color} />
						{Array.from({length: n}).map((__, i) => {
							const w = 180 + rnd(seed + L * 31 + i) * 260;
							const x = ((rnd(seed + L * 17 + i * 3) * (W + 600) - f * speed * (0.3 + k * 1.2)) % (W + 600) + (W + 600)) % (W + 600) - 300;
							const hh = 40 + rnd(seed + i * 7 + L) * 50;
							return (
								<g key={i}>
									<ellipse cx={x} cy={yy + 10} rx={w} ry={hh} fill={color} />
									<ellipse cx={x - w * 0.15} cy={yy - hh * 0.25} rx={w * 0.7} ry={hh * 0.45} fill={light} opacity={0.35 + k * 0.3} />
								</g>
							);
						})}
					</g>
				);
			})}
		</g>
	);
};

// 浮空岛：上面平台 + 树影，下面倒锥形的岩石 + 垂下来的藤
export const FloatIsland: React.FC<{x: number; y: number; s: number; rock: string; top: string; rim?: string; seed?: number; glow?: string}> = ({
	x,
	y,
	s,
	rock,
	top,
	rim = 'rgba(255,220,170,0.5)',
	seed = 1,
	glow,
}) => {
	const f = useCurrentFrame();
	const bob = Math.sin(f * 0.02 + seed) * 4 * s;
	const pts: string[] = [];
	const n = 9;
	for (let i = 0; i <= n; i++) {
		const t = i / n;
		const xx = -120 + t * 240;
		const depth = Math.sin(t * Math.PI) * (110 + rnd(seed + i) * 60) * (0.6 + 0.4 * Math.sin(t * 7 + seed));
		pts.push(`${xx},${Math.max(depth, 8) + rnd(seed + i * 3) * 18}`);
	}
	const bottom = `M -130 0 L ${pts.join(' L ')} L 130 0 Z`;
	return (
		<g transform={`translate(${x} ${y + bob}) scale(${s})`}>
			{glow && <ellipse cx={0} cy={20} rx={170} ry={90} fill={glow} opacity={0.35} filter="url(#b26)" />}
			<path d={bottom} fill={rock} />
			<path d={bottom} fill="none" stroke={rim} strokeWidth={2} opacity={0.5} />
			{/* 垂下的藤 */}
			{Array.from({length: 7}).map((_, i) => {
				const xx = -100 + rnd(seed + i * 11) * 200;
				const len = 30 + rnd(seed + i * 5) * 70;
				const sw = Math.sin(f * 0.03 + i) * 4;
				return <path key={i} d={`M ${xx} 10 Q ${xx + sw} ${len * 0.5} ${xx + sw * 1.6} ${len}`} stroke={top} strokeWidth={1.4} fill="none" opacity={0.7} />;
			})}
			{/* 顶上：草地和树 */}
			<ellipse cx={0} cy={0} rx={134} ry={12} fill={top} />
			{Array.from({length: 6}).map((_, i) => {
				const tx = -95 + rnd(seed + i * 13) * 190;
				const th = 26 + rnd(seed + i * 2.2) * 34;
				return (
					<g key={i}>
						<rect x={tx - 1.5} y={-th * 0.5} width={3} height={th * 0.5} fill={rock} />
						<ellipse cx={tx} cy={-th * 0.62} rx={th * 0.34} ry={th * 0.42} fill={top} />
					</g>
				);
			})}
			<ellipse cx={-30} cy={-4} rx={110} ry={6} fill={rim} opacity={0.35} />
		</g>
	);
};

// 旁白：一个字一个字显出来（从模糊到清楚、微微上浮），到点淡出
export const Narration: React.FC<{text: string; from: number; to: number; y?: number; size?: number; color?: string; font?: string; weight?: number; stagger?: number}> = ({
	text,
	from,
	to,
	y = 578,
	size = 32,
	color = '#f3ead6',
	font = SERIF,
	weight = 500,
	stagger = 1.4,
}) => {
	const f = useCurrentFrame();
	if (f < from - 1 || f > to + 1) return null;
	const out = interpolate(f, [to - 16, to], [1, 0], clamp);
	return (
		<div
			style={{
				position: 'absolute',
				left: 60,
				right: 60,
				top: y,
				textAlign: 'center',
				fontFamily: font,
				fontWeight: weight,
				fontSize: size,
				color,
				letterSpacing: size * 0.14,
				lineHeight: 1.5,
				textShadow: '0 0 22px rgba(0,0,0,0.85), 0 2px 8px rgba(0,0,0,0.95)',
				opacity: out,
			}}
		>
			{Array.from(text).map((c, i) => {
				const t0 = from + i * stagger;
				const a = interpolate(f, [t0, t0 + 12], [0, 1], clamp);
				const b = interpolate(f, [t0, t0 + 16], [1, 0], clamp);
				return (
					<span key={i} style={{opacity: a, filter: `blur(${b * 5}px)`, display: 'inline-block', transform: `translateY(${b * 8}px)`}}>
						{c === ' ' ? ' ' : c}
					</span>
				);
			})}
		</div>
	);
};

// 大标题：金色渐变，字距慢慢收拢，底下一道光
export const BigTitle: React.FC<{text: string; from: number; to: number; y?: number; size?: number; sub?: string}> = ({text, from, to, y = 290, size = 120, sub}) => {
	const f = useCurrentFrame();
	if (f < from - 1 || f > to + 1) return null;
	const a = win(f, from, to, 20, 18);
	const sp = interpolate(f, [from, to], [0.55, 0.28], clamp);
	const line = interpolate(f, [from + 6, from + 40], [0, 1], {...clamp, easing: easeOut});
	return (
		<div style={{position: 'absolute', left: 0, right: 0, top: y, textAlign: 'center', opacity: a}}>
			<div
				style={{
					fontFamily: SERIF,
					fontWeight: 900,
					fontSize: size,
					letterSpacing: size * sp,
					paddingLeft: size * sp,
					background: 'linear-gradient(180deg, #fff6dc 0%, #f2cf7a 45%, #b07a2c 100%)',
					WebkitBackgroundClip: 'text',
					color: 'transparent',
					filter: 'drop-shadow(0 0 24px rgba(242,207,122,0.45)) drop-shadow(0 4px 10px rgba(0,0,0,0.9))',
				}}
			>
				{text}
			</div>
			<div style={{margin: '8px auto 0', width: 520 * line, height: 2, background: 'linear-gradient(90deg, transparent, #f2cf7a, transparent)'}} />
			{sub && (
				<div style={{marginTop: 14, fontFamily: SANS, fontWeight: 500, fontSize: 22, letterSpacing: 10, color: 'rgba(240,230,210,0.85)', paddingLeft: 10}}>{sub}</div>
			)}
		</div>
	);
};

// 天枢碎片：一块发光的菱形晶体（带拖尾时 trail > 0）
export const Shard: React.FC<{x: number; y: number; s?: number; color: string; rot?: number; trail?: number; angle?: number}> = ({x, y, s = 1, color, rot = 0, trail = 0, angle = 0}) => (
	<g>
		{trail > 0 && (
			<g transform={`translate(${x} ${y}) rotate(${angle})`}>
				<path d={`M 0 -6 L ${-trail} 0 L 0 6 Z`} fill={color} opacity={0.55} filter="url(#b4)" />
				<path d={`M 0 -2 L ${-trail * 0.7} 0 L 0 2 Z`} fill="#fff" opacity={0.8} filter="url(#b1)" />
			</g>
		)}
		<g transform={`translate(${x} ${y}) rotate(${rot}) scale(${s})`}>
			<circle r={34} fill={color} opacity={0.35} filter="url(#b16)" />
			<path d="M 0 -26 L 11 -4 L 0 26 L -11 -4 Z" fill={color} />
			<path d="M 0 -26 L 11 -4 L 0 4 Z" fill="#fff" opacity={0.55} />
			<path d="M 0 -26 L -11 -4 L 0 26" fill="none" stroke="#fff" strokeWidth={1.2} opacity={0.8} />
			<circle r={4} fill="#fff" filter="url(#b2)" />
		</g>
	</g>
);

// 光柱（从天上打下来）
export const Pillar: React.FC<{x: number; w: number; color: string; alpha: number; top?: number; bottom?: number}> = ({x, w, color, alpha, top = -50, bottom = H}) => (
	<g opacity={alpha}>
		<rect x={x - w} y={top} width={w * 2} height={bottom - top} fill={color} opacity={0.35} filter="url(#b26)" />
		<rect x={x - w * 0.35} y={top} width={w * 0.7} height={bottom - top} fill={color} opacity={0.7} filter="url(#b6)" />
		<rect x={x - w * 0.08} y={top} width={w * 0.16} height={bottom - top} fill="#fff" filter="url(#b2)" />
	</g>
);
