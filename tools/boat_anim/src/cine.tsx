import React, {useEffect, useState} from 'react';
import {AbsoluteFill, continueRender, delayRender, Easing, Img, interpolate, staticFile, useCurrentFrame} from 'remotion';
import DIMS from './artdims.json';

// 名画过场的公用零件：镜头（名画慢推 / 平移 + 调色 + 粒子）、字幕、左上角标签、大数字、标题、纸片卡片。
// 画面 1920x1080、30 帧/秒。画在 public/art/<key>.jpg（fetch_art.py 下载，清单和出处在 art.json）。
// 胶片颗粒不画进视频（颗粒让视频体积翻几倍），游戏里播放时叠一层（voyage.gd）。

export const W = 1920;
export const H = 1080;
export const FPS = 30;
export const SERIF_SC = "'CxSerifSC', serif";
export const GARAMOND = "'CxGaramond', 'CxSerifSC', serif";
export const MONO = "'CxMono', 'CxSerifSC', monospace";
export const PAPER = '#f0ebe0';
export const INK = '#2a241c';
export const RUST = '#b4532e';

export const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
export const ease = Easing.bezier(0.42, 0, 0.58, 1);
export const easeOut = Easing.bezier(0.16, 1, 0.3, 1);
export const rnd = (i: number) => {
	const x = Math.sin(i * 127.1 + 311.7) * 43758.5453;
	return x - Math.floor(x);
};

// ---------------------------------------------------------------- 字体（等字体加载完再截帧）
const FONTS: [string, string, FontFaceDescriptors][] = [
	['CxSerifSC', 'fonts/NotoSerifSC.ttf', {weight: '200 900'}],
	['CxGaramond', 'fonts/EBGaramond.ttf', {weight: '400 800'}],
	['CxGaramond', 'fonts/EBGaramond-Italic.ttf', {weight: '400 800', style: 'italic'}],
	['CxMono', 'fonts/CourierPrime.ttf', {}],
];
let fontsReady: Promise<void> | null = null;
const loadFonts = () => {
	if (!fontsReady) {
		fontsReady = Promise.all(
			FONTS.map(([fam, file, desc]) =>
				new FontFace(fam, `url(${staticFile(file)})`, desc).load().then((ff) => {
					document.fonts.add(ff);
				}),
			),
		).then(() => undefined);
	}
	return fontsReady;
};
const useFonts = () => {
	const [h] = useState(() => delayRender('fonts'));
	useEffect(() => {
		loadFonts().then(() => continueRender(h));
	}, [h]);
};

// 一部片子：黑底 + 内容 + 暗角 + 开头结尾的黑场
export const Film: React.FC<{total: number; fadeIn?: number; fadeOut?: number; children: React.ReactNode}> = ({total, fadeIn = 18, fadeOut = 18, children}) => {
	useFonts();
	const f = useCurrentFrame();
	const black = Math.max(fadeIn > 0 ? interpolate(f, [0, fadeIn], [1, 0], clamp) : 0, fadeOut > 0 ? interpolate(f, [total - fadeOut, total - 1], [0, 1], clamp) : 0);
	return (
		<AbsoluteFill style={{background: '#000', overflow: 'hidden'}}>
			{children}
			<AbsoluteFill style={{background: 'radial-gradient(ellipse 75% 70% at 50% 48%, rgba(0,0,0,0) 52%, rgba(0,0,0,0.5) 88%, rgba(0,0,0,0.72) 100%)'}} />
			<AbsoluteFill style={{background: '#000', opacity: black}} />
		</AbsoluteFill>
	);
};

// ---------------------------------------------------------------- 镜头
// 镜头位置 Cam = [画面中心在原画里的横坐标 0~1, 纵坐标 0~1, 放大倍数（1 = 原画刚好铺满画面）]
export type Cam = [number, number, number];
export type Grade = {sat?: number; con?: number; bri?: number; sepia?: number; warm?: number};
export type Fx = 'dust' | 'embers' | 'snow' | 'mist' | 'none';
export type Glow = {x: number; y: number; r: number; color: string; a: number; pulse?: number};

type ShotProps = {
	art: keyof typeof DIMS;
	from: number;
	to: number;
	a: Cam;
	b: Cam;
	fadeIn?: number; // 0 = 硬切
	fadeOut?: number; // 0 = 不淡出（被下一个镜头盖住，做交叉溶解）
	grade?: Grade;
	fx?: Fx;
	glow?: Glow; // 贴在画上的光（坐标是原画里的 0~1）
	shake?: [number, number, number]; // [开始帧, 结束帧, 幅度像素]
	children?: React.ReactNode;
};

export const Shot: React.FC<ShotProps> = (p) => {
	const f = useCurrentFrame();
	if (f < p.from || f > p.to) return null;
	const k = ease(interpolate(f, [p.from, p.to], [0, 1], clamp));
	const [iw, ih] = DIMS[p.art] as number[];
	const z = p.a[2] + (p.b[2] - p.a[2]) * k;
	const s = Math.max(W / iw, H / ih) * z;
	const hw = W / 2 / (iw * s);
	const hh = H / 2 / (ih * s);
	const cx = Math.min(Math.max(p.a[0] + (p.b[0] - p.a[0]) * k, hw), 1 - hw);
	const cy = Math.min(Math.max(p.a[1] + (p.b[1] - p.a[1]) * k, hh), 1 - hh);
	let x = W / 2 - cx * iw * s;
	let y = H / 2 - cy * ih * s;
	if (p.shake && f >= p.shake[0] && f <= p.shake[1]) {
		const amp = p.shake[2] * interpolate(f, [p.shake[0], p.shake[1]], [1, 0], clamp);
		x += (rnd(f * 3.1) - 0.5) * 2 * amp;
		y += (rnd(f * 7.7) - 0.5) * 2 * amp;
	}
	const fi = p.fadeIn ?? 14;
	const fo = p.fadeOut ?? 14;
	const op = Math.min(fi > 0 ? interpolate(f, [p.from, p.from + fi], [0, 1], clamp) : 1, fo > 0 ? interpolate(f, [p.to - fo, p.to], [1, 0], clamp) : 1);
	const g = {sat: 0.9, con: 1.06, bri: 0.93, sepia: 0.1, warm: 0.22, ...p.grade};
	const local = f - p.from;
	let glow = null;
	if (p.glow) {
		const gl = p.glow;
		const pulse = 1 + (gl.pulse ?? 0.08) * Math.sin(local * 0.09);
		glow = (
			<div
				style={{
					position: 'absolute',
					left: x + gl.x * iw * s - gl.r * pulse,
					top: y + gl.y * ih * s - gl.r * pulse,
					width: gl.r * 2 * pulse,
					height: gl.r * 2 * pulse,
					borderRadius: '50%',
					background: `radial-gradient(circle, ${gl.color} 0%, rgba(0,0,0,0) 70%)`,
					opacity: gl.a,
					mixBlendMode: 'screen',
				}}
			/>
		);
	}
	return (
		<AbsoluteFill style={{opacity: op, overflow: 'hidden'}}>
			<Img
				src={staticFile(`art/${p.art}.jpg`)}
				style={{
					position: 'absolute',
					left: 0,
					top: 0,
					width: iw,
					height: ih,
					maxWidth: 'none',
					transformOrigin: '0 0',
					transform: `translate(${x}px, ${y}px) scale(${s})`,
					filter: `sepia(${g.sepia}) saturate(${g.sat}) contrast(${g.con}) brightness(${g.bri})`,
				}}
			/>
			{/* 暖色：高光偏琥珀，暗部压一点青灰 */}
			<AbsoluteFill style={{background: 'linear-gradient(180deg, rgba(255,190,110,1) 0%, rgba(255,170,90,1) 55%, rgba(40,50,70,1) 100%)', mixBlendMode: 'soft-light', opacity: g.warm}} />
			{glow}
			{p.fx && p.fx !== 'none' ? <Particles kind={p.fx} t={local} /> : null}
			{/* 字幕和左上角标签底下压暗一点（亮的画上也看得清） */}
			<AbsoluteFill style={{background: 'linear-gradient(0deg, rgba(0,0,0,0.5) 0%, rgba(0,0,0,0.22) 18%, rgba(0,0,0,0) 34%)'}} />
			<AbsoluteFill style={{background: 'radial-gradient(ellipse 1000px 480px at 0% 0%, rgba(0,0,0,0.58) 0%, rgba(0,0,0,0.25) 50%, rgba(0,0,0,0) 100%)'}} />
			{p.children}
		</AbsoluteFill>
	);
};

// ---------------------------------------------------------------- 粒子：光尘 / 火星 / 雪 / 雾
export const Particles: React.FC<{kind: Fx; t: number}> = ({kind, t}) => {
	if (kind === 'mist') {
		return (
			<AbsoluteFill style={{mixBlendMode: 'screen'}}>
				{[0, 1, 2].map((i) => {
					const x = ((rnd(i + 3) * W + t * (0.6 + i * 0.3)) % (W + 1400)) - 700;
					return <div key={i} style={{position: 'absolute', left: x, top: 380 + i * 180, width: 1400, height: 420, borderRadius: '50%', background: 'radial-gradient(ellipse, rgba(230,225,215,0.16) 0%, rgba(0,0,0,0) 70%)'}} />;
				})}
			</AbsoluteFill>
		);
	}
	const n = kind === 'snow' ? 130 : kind === 'embers' ? 70 : 46;
	const dots = [];
	for (let i = 0; i < n; i++) {
		const r1 = rnd(i * 1.3 + 1);
		const r2 = rnd(i * 2.7 + 2);
		const r3 = rnd(i * 5.1 + 3);
		let x = 0;
		let y = 0;
		let size = 0;
		let color = '';
		let a = 0;
		if (kind === 'snow') {
			const sp = 1.2 + r3 * 2.2;
			y = ((r2 * (H + 60) + t * sp) % (H + 60)) - 30;
			x = r1 * W + Math.sin(t * 0.03 + i) * 24 - t * 0.5;
			x = ((x % W) + W) % W;
			size = 2 + r3 * 5;
			color = 'rgba(245,248,255,1)';
			a = 0.35 + r3 * 0.5;
		} else if (kind === 'embers') {
			const sp = 1.4 + r3 * 2.6;
			y = H + 30 - ((r2 * (H + 60) + t * sp) % (H + 60));
			x = r1 * W + Math.sin(t * 0.05 + i * 2) * 30;
			size = 2 + r3 * 4;
			color = r3 > 0.5 ? 'rgba(255,170,70,1)' : 'rgba(255,110,40,1)';
			a = (0.4 + 0.6 * Math.abs(Math.sin(t * 0.12 + i))) * 0.9;
		} else {
			const sp = 0.25 + r3 * 0.45;
			y = H + 20 - ((r2 * (H + 40) + t * sp) % (H + 40));
			x = r1 * W + Math.sin(t * 0.02 + i) * 40;
			size = 2 + r3 * 4;
			color = 'rgba(255,226,170,1)';
			a = (0.25 + 0.45 * Math.abs(Math.sin(t * 0.05 + i * 1.7))) * 0.8;
		}
		dots.push(
			<div
				key={i}
				style={{
					position: 'absolute',
					left: x - size,
					top: y - size,
					width: size * 2,
					height: size * 2,
					borderRadius: '50%',
					background: `radial-gradient(circle, ${color} 0%, rgba(0,0,0,0) 70%)`,
					opacity: a,
				}}
			/>,
		);
	}
	return <AbsoluteFill style={{mixBlendMode: kind === 'snow' ? 'normal' : 'screen'}}>{dots}</AbsoluteFill>;
};

// ---------------------------------------------------------------- 字：进出场
const win = (f: number, a: number, b: number, fi = 12, fo = 12) => Math.min(interpolate(f, [a, a + fi], [0, 1], clamp), interpolate(f, [b - fo, b], [1, 0], clamp));

// 底部字幕：中文衬线 + 英文斜体
export const Sub: React.FC<{zh: string; en?: string; from: number; to: number; quote?: boolean}> = ({zh, en, from, to, quote}) => {
	const f = useCurrentFrame();
	if (f < from || f > to) return null;
	const a = win(f, from, to, 12, 12);
	const dy = interpolate(f, [from, from + 18], [8, 0], {...clamp, easing: easeOut});
	return (
		<div style={{position: 'absolute', left: 160, right: 160, bottom: 92, textAlign: 'center', opacity: a, transform: `translateY(${dy}px)`}}>
			<div
				style={{
					fontFamily: SERIF_SC,
					fontWeight: 500,
					fontSize: 40,
					letterSpacing: '0.08em',
					color: quote ? '#ffe6c2' : 'rgba(255,250,240,0.96)',
					textShadow: '0 2px 14px rgba(0,0,0,0.75), 0 0 2px rgba(0,0,0,0.6)',
				}}
			>
				{zh}
			</div>
			{en ? (
				<div style={{fontFamily: GARAMOND, fontStyle: 'italic', fontSize: 25, marginTop: 12, letterSpacing: '0.02em', color: 'rgba(236,228,214,0.72)', textShadow: '0 2px 10px rgba(0,0,0,0.8)'}}>{en}</div>
			) : null}
		</div>
	);
};

// 左上角：细线 + 标签 + 小字说明（像纪录片里的时间 / 地点标注）
export const Label: React.FC<{top: string; sub?: string; from: number; to: number; fade?: number}> = ({top, sub, from, to, fade = 16}) => {
	const f = useCurrentFrame();
	if (f < from || f > to) return null;
	const a = win(f, from, to, fade, Math.min(fade, 14));
	const line = interpolate(f, [from, from + fade + 8], [0, 64], {...clamp, easing: easeOut});
	return (
		<div style={{position: 'absolute', left: 104, top: 92, opacity: a}}>
			<div style={{display: 'flex', alignItems: 'center', gap: 20}}>
				<div style={{width: line, height: 1, background: 'rgba(255,248,235,0.75)'}} />
				<div style={{fontFamily: GARAMOND, fontSize: 30, letterSpacing: '0.14em', color: 'rgba(255,250,240,0.95)', textShadow: '0 2px 10px rgba(0,0,0,0.7)'}}>{top}</div>
			</div>
			{sub ? (
				<div style={{marginLeft: 84, marginTop: 8, fontFamily: SERIF_SC, fontSize: 18, letterSpacing: '0.24em', color: 'rgba(245,238,225,0.78)', textShadow: '0 2px 8px rgba(0,0,0,0.8)'}}>{sub}</div>
			) : null}
		</div>
	);
};

// 左上角大数字（从 0 滚上去）
export const BigStat: React.FC<{value: number; unit: string; from: number; to: number; top?: number}> = ({value, unit, from, to, top = 176}) => {
	const f = useCurrentFrame();
	if (f < from || f > to) return null;
	const a = win(f, from, to, 14, 14);
	const v = Math.round(value * interpolate(f, [from, from + 40], [0, 1], {...clamp, easing: easeOut}));
	return (
		<div style={{position: 'absolute', left: 104, top, opacity: a}}>
			<div style={{fontFamily: GARAMOND, fontSize: 96, lineHeight: 1, letterSpacing: '0.02em', color: 'rgba(255,250,240,0.97)', textShadow: '0 3px 18px rgba(0,0,0,0.6)'}}>{v.toLocaleString('en-US')}</div>
			<div style={{marginTop: 10, fontFamily: SERIF_SC, fontSize: 18, letterSpacing: '0.3em', color: 'rgba(245,238,225,0.8)', textShadow: '0 2px 8px rgba(0,0,0,0.8)'}}>{unit}</div>
		</div>
	);
};

// 大标题（居中）：眉题 + 大字 + 英文
export const Title: React.FC<{zh: string; en?: string; kicker?: string; from: number; to: number; size?: number; y?: number}> = ({zh, en, kicker, from, to, size = 150, y = 0}) => {
	const f = useCurrentFrame();
	if (f < from || f > to) return null;
	const a = win(f, from, to, 20, 16);
	const sc = interpolate(f, [from, to], [1.04, 1.0], clamp);
	const spread = interpolate(f, [from, from + 40], [0.18, 0.32], {...clamp, easing: easeOut});
	return (
		<AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', opacity: a, transform: `translateY(${y}px) scale(${sc})`}}>
			<div style={{position: 'absolute', left: W / 2 - 900, top: H / 2 - 330, width: 1800, height: 660, background: 'radial-gradient(ellipse closest-side, rgba(0,0,0,0.5) 0%, rgba(0,0,0,0.24) 55%, rgba(0,0,0,0) 100%)'}} />
			{kicker ? (
				<div style={{display: 'flex', alignItems: 'center', gap: 22, marginBottom: 18}}>
					<div style={{width: 70, height: 1, background: 'rgba(255,240,215,0.7)'}} />
					<div style={{fontFamily: SERIF_SC, fontSize: 22, letterSpacing: '0.4em', color: 'rgba(255,236,205,0.9)', textShadow: '0 2px 10px rgba(0,0,0,0.8)'}}>{kicker}</div>
					<div style={{width: 70, height: 1, background: 'rgba(255,240,215,0.7)'}} />
				</div>
			) : null}
			<div style={{fontFamily: SERIF_SC, fontWeight: 600, fontSize: size, lineHeight: 1.1, letterSpacing: `${spread}em`, marginLeft: `${spread}em`, color: '#fbf5ea', textShadow: '0 4px 30px rgba(0,0,0,0.65), 0 0 60px rgba(255,210,150,0.25)'}}>{zh}</div>
			{en ? <div style={{marginTop: 20, fontFamily: GARAMOND, fontSize: 24, letterSpacing: '0.42em', marginLeft: '0.42em', color: 'rgba(245,236,220,0.9)', textShadow: '0 2px 10px rgba(0,0,0,0.95), 0 0 3px rgba(0,0,0,0.8)'}}>{en}</div> : null}
		</AbsoluteFill>
	);
};

// 米白纸片卡片（像截图里那张"下一个词"的小卡）：从右边滑进来，一行一行出现
export type CardRow = {key: string; title: string; desc: string; bar?: number};
export const PaperCard: React.FC<{from: number; to: number; head: string; headEn: string; rows: CardRow[]; foot?: string; x?: number; y?: number; width?: number}> = ({from, to, head, headEn, rows, foot, x = 930, y = 110, width = 900}) => {
	const f = useCurrentFrame();
	if (f < from || f > to) return null;
	const a = win(f, from, to, 16, 16);
	const dx = interpolate(f, [from, from + 26], [60, 0], {...clamp, easing: easeOut});
	const typed = Math.floor(interpolate(f, [from + 6, from + 30], [0, headEn.length], clamp));
	return (
		<div
			style={{
				position: 'absolute',
				left: x,
				top: y,
				width,
				opacity: a,
				transform: `translateX(${dx}px) rotate(-0.8deg)`,
				background: `radial-gradient(ellipse at 30% 20%, #f7f3ea 0%, ${PAPER} 60%, #e6dfcf 100%)`,
				boxShadow: '0 30px 70px rgba(0,0,0,0.5), 0 2px 6px rgba(0,0,0,0.3)',
				padding: '40px 50px 36px',
				color: INK,
			}}
		>
			<div style={{fontFamily: MONO, fontSize: 18, letterSpacing: '0.12em', color: 'rgba(42,36,28,0.7)', height: 24}}>
				{headEn.slice(0, typed)}
				<span style={{opacity: f % 30 < 15 ? 1 : 0}}>_</span>
			</div>
			<div style={{fontFamily: SERIF_SC, fontWeight: 700, fontSize: 44, letterSpacing: '0.2em', marginTop: 6}}>{head}</div>
			<div style={{height: 2, background: RUST, marginTop: 16, width: interpolate(f, [from + 10, from + 40], [0, width - 100], {...clamp, easing: easeOut})}} />
			{rows.map((r, i) => {
				const t0 = from + 34 + i * 30;
				const ra = interpolate(f, [t0, t0 + 14], [0, 1], clamp);
				const bar = r.bar ?? 0;
				return (
					<div key={i} style={{display: 'flex', gap: 22, marginTop: 22, opacity: ra, alignItems: 'flex-start'}}>
						<div style={{width: 54, height: 54, border: `1.5px solid ${INK}`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: MONO, fontWeight: 700, fontSize: 26, flexShrink: 0}}>{r.key}</div>
						<div style={{flex: 1}}>
							<div style={{display: 'flex', alignItems: 'center', gap: 16}}>
								<div style={{fontFamily: SERIF_SC, fontWeight: 700, fontSize: 31, letterSpacing: '0.1em'}}>{r.title}</div>
								{bar > 0 ? <div style={{height: 5, background: RUST, width: interpolate(f, [t0 + 4, t0 + 30], [0, bar * 220], {...clamp, easing: easeOut})}} /> : null}
							</div>
							<div style={{fontFamily: SERIF_SC, fontSize: 23, lineHeight: 1.55, color: 'rgba(42,36,28,0.85)', marginTop: 4}}>{r.desc}</div>
						</div>
					</div>
				);
			})}
			{foot ? (
				<div style={{marginTop: 26, paddingTop: 14, borderTop: '1px dashed rgba(42,36,28,0.35)', fontFamily: MONO, fontSize: 20, color: 'rgba(42,36,28,0.8)', opacity: interpolate(f, [from + 34 + rows.length * 30, from + 50 + rows.length * 30], [0, 1], clamp)}}>
					{foot}
				</div>
			) : null}
		</div>
	);
};

// 天倾：五块碎片拖着光尾坠下（颜色和游戏里五块天枢一样）
const SHARDS = ['#7dffc4', '#ff8fb0', '#ffb45a', '#8fe6ff', '#9d8cff'];
export const ShardFall: React.FC<{from: number}> = ({from}) => {
	const f = useCurrentFrame() - from;
	if (f < 0 || f > 120) return null;
	return (
		<AbsoluteFill style={{mixBlendMode: 'screen'}}>
			{SHARDS.map((c, i) => {
				const t0 = i * 12;
				const p = interpolate(f, [t0, t0 + 60], [0, 1], {...clamp, easing: Easing.in(Easing.quad)});
				if (f < t0 || p >= 1) return null;
				const sx = 700 + i * 170 + rnd(i) * 80;
				const x = sx + p * (260 - i * 90);
				const y = -80 + p * 1200;
				const ang = (Math.atan2(1200, 260 - i * 90) * 180) / Math.PI;
				return (
					<div key={i}>
						<div style={{position: 'absolute', left: x - 260, top: y - 3, width: 260, height: 6, transformOrigin: '100% 50%', transform: `rotate(${ang}deg)`, background: `linear-gradient(90deg, rgba(0,0,0,0), ${c})`, filter: 'blur(2px)'}} />
						<div style={{position: 'absolute', left: x - 40, top: y - 40, width: 80, height: 80, borderRadius: '50%', background: `radial-gradient(circle, #ffffff 0%, ${c} 25%, rgba(0,0,0,0) 70%)`}} />
					</div>
				);
			})}
		</AbsoluteFill>
	);
};

// 白光一闪（天倾、天门开）
export const Flash: React.FC<{at: number; len?: number; color?: string; max?: number}> = ({at, len = 24, color = '#fff4e0', max = 0.85}) => {
	const f = useCurrentFrame();
	if (f < at || f > at + len) return null;
	const a = interpolate(f, [at, at + 3, at + len], [0, max, 0], clamp);
	return <AbsoluteFill style={{background: color, opacity: a, mixBlendMode: 'screen'}} />;
};
