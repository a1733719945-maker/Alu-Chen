import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame} from 'remotion';
import {BigTitle, clamp, CloudSea, Defs, easeInOut, easeOut, Fade, FloatIsland, Grain, H, Letterbox, Motes, Narration, Pillar, rnd, SERIF, Shard, Stars, Vignette, W, win} from './lib';
import {Boat, Child, Gate} from './figures';

// ================================================================ 渡海（8 秒）：黄昏的云海，一叶小船挂着灯从浮岛之间穿过去，前面的岛亮着光
export const VOYAGE_FRAMES = 240;

export const Voyage2: React.FC = () => {
	const f = useCurrentFrame();
	const cam = interpolate(f, [0, 240], [0, -120], clamp);
	const push = interpolate(f, [0, 240], [1, 1.08], clamp);
	const boatX = interpolate(f, [0, 240], [180, 820], {...clamp, easing: easeInOut});
	return (
		<AbsoluteFill style={{background: '#000'}}>
			<svg width={W} height={H}>
				<Defs />
				<defs>
					<linearGradient id="vo_sky" x1="0" y1="0" x2="0" y2="1">
						<stop offset="0%" stopColor="#101a3c" />
						<stop offset="45%" stopColor="#6b4466" />
						<stop offset="70%" stopColor="#f0a36e" />
						<stop offset="100%" stopColor="#ffd9a8" />
					</linearGradient>
				</defs>
				<rect width={W} height={H} fill="url(#vo_sky)" />
				<Stars n={70} seed={5} alpha={0.45} h={260} />
				<circle cx={W * 0.78} cy={330} r={58} fill="#fff4dc" filter="url(#b6)" />
				<circle cx={W * 0.78} cy={330} r={240} fill="#ffc98a" opacity={0.35} filter="url(#b40)" />
				{/* 光束从云缝里打下来 */}
				{Array.from({length: 6}).map((_, i) => (
					<path key={i} d={`M ${W * 0.78} 330 L ${200 + i * 170} ${H} L ${260 + i * 170} ${H} Z`} fill="#ffd8a0" opacity={0.05 + 0.03 * Math.sin(f * 0.04 + i)} filter="url(#b10)" />
				))}
				<g transform={`translate(${W / 2 + cam * 0.2} ${H / 2}) scale(${push}) translate(${-W / 2} ${-H / 2})`}>
					<FloatIsland x={1020} y={250} s={0.5} rock="#2c2032" top="#3b2c42" seed={21} glow="#ffe0a0" />
					<Pillar x={1020} w={18} color="#ffe6b0" alpha={0.55} top={-100} bottom={240} />
					<FloatIsland x={300 + cam * 0.4} y={300} s={0.4} rock="#35283a" top="#453650" seed={4} />
					<CloudSea y={430} color="#c98a7a" light="#ffe1bd" layers={3} speed={1.2} seed={17} />
					<g transform={`translate(${cam * 0.9} 0)`}>
						<FloatIsland x={1240} y={420} s={1.2} rock="#1a121c" top="#241a28" seed={31} rim="rgba(255,190,140,0.7)" />
					</g>
				</g>
				<Boat x={boatX} y={470 + Math.sin(f * 0.05) * 5} s={0.9} />
				{/* 船划开的云浪 */}
				{Array.from({length: 10}).map((_, i) => {
					const t = (f + i * 7) % 70;
					return <ellipse key={i} cx={boatX - 40 - t * 3} cy={512} rx={10 + t * 1.2} ry={3 + t * 0.2} fill="#ffe8cc" opacity={interpolate(t, [0, 70], [0.5, 0], clamp)} filter="url(#b4)" />;
				})}
				<CloudSea y={560} color="#a8716a" light="#ffd2ad" layers={2} speed={2.4} seed={23} />
				<Motes n={40} seed={8} color="#fff0c8" y0={250} y1={H} speed={0.3} size={2.2} alpha={0.7} />
			</svg>
			{/* 下半部分压暗，游戏叠的"前往 · 第几章"看得清 */}
			<div style={{position: 'absolute', left: 0, right: 0, bottom: 0, height: 300, background: 'linear-gradient(0deg, rgba(0,0,0,0.65), rgba(0,0,0,0))'}} />
			<Vignette strength={0.6} />
			<Grain amount={0.07} />
			<Letterbox h={44} />
			<Fade opacity={interpolate(f, [0, 12], [1, 0], clamp) + interpolate(f, [226, 240], [0, 1], clamp)} />
		</AbsoluteFill>
	);
};

// ================================================================ 飞升（26 秒）：五块碎片归位 → 天门重开 → 飞升 → 门后是九重天 → 轮回
export const ASCEND_FRAMES = 780;
const SH = ['#7dffc4', '#ff8fb0', '#ffb45a', '#8fe6ff', '#9d8cff'];

export const Ascend: React.FC = () => {
	const f = useCurrentFrame();
	const gateIn = interpolate(f, [120, 220], [0, 1], clamp);
	const open = interpolate(f, [220, 330], [0, 1], {...clamp, easing: easeInOut});
	const white = interpolate(f, [300, 340, 400], [0, 1, 0], clamp);
	const up = interpolate(f, [420, 640], [0, 1], {...clamp, easing: easeInOut});
	return (
		<AbsoluteFill style={{background: '#000'}}>
			<svg width={W} height={H}>
				<Defs />
				<defs>
					<radialGradient id="as_bg" cx="50%" cy="45%" r="75%">
						<stop offset="0%" stopColor="#1b2146" />
						<stop offset="100%" stopColor="#02030a" />
					</radialGradient>
				</defs>
				<rect width={W} height={H} fill="url(#as_bg)" />
				{f < 420 && (
					<g>
						<Stars n={200} seed={71} />
						{/* 五块碎片绕圈收拢 */}
						{SH.map((c, i) => {
							const a = (i / 5) * Math.PI * 2 + f * 0.03;
							const r = interpolate(f, [0, 200], [320, 0], {...clamp, easing: easeInOut});
							const x = W / 2 + Math.cos(a) * r;
							const y = 330 + Math.sin(a) * r * 0.45;
							return f < 215 ? <Shard key={i} x={x} y={y} s={0.8} color={c} rot={f * 4 + i * 40} /> : null;
						})}
						{/* 碎片连成门的轮廓，再亮起来 */}
						<Gate x={W / 2} y={420} s={0.95} open={open} alpha={gateIn} />
						<Pillar x={W / 2} w={40 + open * 160} color="#fff1c8" alpha={open} top={-100} bottom={560} />
						{/* 飞升的人：从门前升起 */}
						<g transform={`translate(${W / 2} ${600 - interpolate(f, [300, 420], [0, 260], clamp)})`} opacity={interpolate(f, [280, 320], [0, 1], clamp)}>
							<Child x={0} y={0} s={1.3} rim="#fff6d8" />
						</g>
						<CloudSea y={580} color="#1a2140" light="#6d7fc0" layers={2} speed={0.6} seed={5} />
					</g>
				)}
				{f >= 400 && (
					<g transform={`translate(0 ${up * 520})`}>
						{/* 九重天：一层叠一层破碎的星海，往上看不到头 */}
						{Array.from({length: 9}).map((_, L) => {
							const y = 520 - L * 150;
							const col = ['#8fa8ff', '#a38cff', '#ff9fd0', '#ffc08a', '#8fffe0', '#8fd8ff', '#c8a0ff', '#ffe08a', '#ffffff'][L];
							return (
								<g key={L} opacity={0.95 - L * 0.06}>
									{/* 一层星云带 + 一圈碎裂的晶石（像塌掉的天的地面） */}
									<ellipse cx={W / 2} cy={y} rx={760 - L * 30} ry={60} fill={col} opacity={0.14} filter="url(#b26)" />
									<ellipse cx={W / 2 + Math.sin(L + f * 0.01) * 80} cy={y + 10} rx={420} ry={18} fill={col} opacity={0.18} filter="url(#b10)" />
									{Array.from({length: 13}).map((_, k) => {
										const x0 = 20 + k * 98 + rnd(L * 13 + k) * 40;
										const w = 50 + rnd(L * 7 + k) * 90;
										const hgt = 14 + rnd(L * 5 + k) * 26;
										const tilt = (rnd(L * 3 + k) - 0.5) * 22 + Math.sin(f * 0.02 + k + L) * 3;
										const bob = Math.sin(f * 0.03 + k * 1.7 + L) * 4;
										const pts = `M ${x0} ${y + bob} l ${w * 0.45} ${-hgt} l ${w * 0.55} ${hgt * 0.6} l ${-w * 0.2} ${hgt * 0.9} l ${-w * 0.6} ${hgt * 0.2} Z`;
										return (
											<g key={k} transform={`rotate(${tilt} ${x0} ${y})`}>
												<path d={pts} fill={col} opacity={0.18} filter="url(#b4)" />
												<path d={pts} fill="#0a0e20" stroke={col} strokeWidth={1.4} opacity={0.95} />
												<path d={`M ${x0 + w * 0.45} ${y + bob - hgt} l ${w * 0.1} ${hgt * 1.1}`} stroke={col} strokeWidth={0.8} opacity={0.6} />
											</g>
										);
									})}
									<Stars n={40} seed={200 + L * 9} alpha={0.6} h={H} />
								</g>
							);
						})}
					</g>
				)}
				<Motes n={60} seed={17} color="#fff3cf" y0={0} y1={H} speed={0.8} size={2.4} alpha={0.8} />
			</svg>
			<Narration text="五块天枢，归位。" from={30} to={130} />
			<Narration text="天门，重开。" from={170} to={290} size={40} />
			<Narration text="灵气归天，万兽安驯。你踏进了光里——" from={340} to={430} />
			<Narration text="可门后不是天。" from={450} to={540} size={38} />
			<Narration text="是九重天。一层叠一层，每一重都塌着。" from={540} to={640} />
			<Narration text="你站着的，只是第一重。" from={640} to={712} size={34} color="#ffe2b8" />
			<BigTitle text="轮回" from={704} to={780} size={130} y={230} sub="第二重天" />
			<Fade color="#fff" opacity={white} />
			<Vignette strength={0.7} />
			<Grain amount={0.08} />
			<Letterbox h={48} />
			<Fade opacity={interpolate(f, [0, 20], [1, 0], clamp) + interpolate(f, [765, 780], [0, 1], clamp)} />
		</AbsoluteFill>
	);
};

// ================================================================ 进洞天（3.6 秒）：天上裂开一道口子，里面是旋转的紫色星云，把人吸进去，白光
export const DUNGEON_FRAMES = 108;

export const DungeonGate: React.FC = () => {
	const f = useCurrentFrame();
	const open = interpolate(f, [4, 44], [0, 1], {...clamp, easing: easeOut});
	const zoom = interpolate(f, [40, 104], [1, 3.2], {...clamp, easing: Easing2});
	const flash = interpolate(f, [92, 104, 108], [0, 1, 1], clamp);
	return (
		<AbsoluteFill style={{background: '#000'}}>
			<svg width={W} height={H}>
				<Defs />
				<defs>
					<radialGradient id="dg_core" cx="50%" cy="50%" r="50%">
						<stop offset="0%" stopColor="#ffffff" />
						<stop offset="18%" stopColor="#d9b8ff" />
						<stop offset="50%" stopColor="#6a3cc8" />
						<stop offset="100%" stopColor="#12081f" stopOpacity={0} />
					</radialGradient>
				</defs>
				<rect width={W} height={H} fill="#07050f" />
				<Stars n={140} seed={301} />
				<g transform={`translate(${W / 2} ${H / 2}) scale(${zoom}) rotate(${f * 0.6}) translate(${-W / 2} ${-H / 2})`}>
					<ellipse cx={W / 2} cy={H / 2} rx={420 * open} ry={250 * open} fill="url(#dg_core)" opacity={0.95} />
					{/* 漩涡：一圈圈转着的弧 */}
					{Array.from({length: 26}).map((_, i) => {
						const r = 40 + i * 14;
						const a0 = f * (0.08 + i * 0.004) + i;
						const x1 = W / 2 + Math.cos(a0) * r * 1.6 * open;
						const y1 = H / 2 + Math.sin(a0) * r * open;
						const x2 = W / 2 + Math.cos(a0 + 1.4) * r * 1.6 * open;
						const y2 = H / 2 + Math.sin(a0 + 1.4) * r * open;
						return <path key={i} d={`M ${x1} ${y1} A ${r * 1.6 * open} ${r * open} 0 0 1 ${x2} ${y2}`} stroke={i % 3 ? '#b58cff' : '#ffffff'} strokeWidth={1.5 + (i % 4)} fill="none" opacity={0.55} filter="url(#b2)" />;
					})}
					{/* 裂口的边：锯齿状的光 */}
					<path
						d={Array.from({length: 40})
							.map((_, i) => {
								const a = (i / 40) * Math.PI * 2;
								const rr = (1 + (rnd(i) - 0.5) * 0.35) * 440 * open;
								return `${i ? 'L' : 'M'} ${W / 2 + Math.cos(a) * rr} ${H / 2 + Math.sin(a) * rr * 0.6}`;
							})
							.join(' ') + ' Z'}
						fill="none"
						stroke="#e8d4ff"
						strokeWidth={3}
						filter="url(#glowBig)"
					/>
					{/* 碎片往里飞 */}
					{Array.from({length: 50}).map((_, i) => {
						const a = rnd(i) * Math.PI * 2;
						const t = ((f * (1 + rnd(i * 3)) + rnd(i * 7) * 100) % 100) / 100;
						const rr = (1 - t) * 700;
						return <rect key={i} x={W / 2 + Math.cos(a) * rr} y={H / 2 + Math.sin(a) * rr * 0.6} width={4 + rnd(i) * 10} height={2 + rnd(i * 2) * 5} fill="#e3d0ff" opacity={t} transform={`rotate(${a * 57} ${W / 2 + Math.cos(a) * rr} ${H / 2 + Math.sin(a) * rr * 0.6})`} />;
					})}
				</g>
			</svg>
			<div style={{position: 'absolute', left: 0, right: 0, bottom: 0, height: 280, background: 'linear-gradient(0deg, rgba(0,0,0,0.6), rgba(0,0,0,0))'}} />
			<Vignette strength={0.8} />
			<Grain amount={0.08} />
			<Fade color="#f4ecff" opacity={flash} />
			<Fade opacity={interpolate(f, [0, 6], [1, 0], clamp)} />
		</AbsoluteFill>
	);
};

function Easing2(t: number) {
	return t * t * t;
}

// ================================================================ 去猎场（4 秒）：月下的荒原，发光的爪痕一道道往远处延伸，黑暗里睁开一只琥珀色的眼睛
export const HUNT_FRAMES = 120;

export const HuntGate: React.FC = () => {
	const f = useCurrentFrame();
	const eye = interpolate(f, [70, 92], [0, 1], {...clamp, easing: easeOut});
	const flash = interpolate(f, [104, 116, 120], [0, 1, 1], clamp);
	const push = interpolate(f, [0, 120], [1, 1.15], clamp);
	return (
		<AbsoluteFill style={{background: '#000'}}>
			<svg width={W} height={H}>
				<Defs />
				<defs>
					<linearGradient id="hg_sky" x1="0" y1="0" x2="0" y2="1">
						<stop offset="0%" stopColor="#060a16" />
						<stop offset="55%" stopColor="#1c2440" />
						<stop offset="62%" stopColor="#2c2a3a" />
					</linearGradient>
					<linearGradient id="hg_ground" x1="0" y1="0" x2="0" y2="1">
						<stop offset="0%" stopColor="#15141c" />
						<stop offset="100%" stopColor="#050506" />
					</linearGradient>
				</defs>
				<rect width={W} height={H} fill="url(#hg_sky)" />
				<Stars n={120} seed={401} h={360} />
				<circle cx={900} cy={170} r={46} fill="#f3f0e0" filter="url(#b2)" />
				<circle cx={900} cy={170} r={160} fill="#c8d4ff" opacity={0.18} filter="url(#b40)" />
				<g transform={`translate(${W / 2} ${H / 2}) scale(${push}) translate(${-W / 2} ${-H / 2})`}>
					<path d={`M 0 400 ${Array.from({length: 17}).map((_, i) => `L ${i * 80} ${392 - rnd(i + 40) * 50}`).join(' ')} L ${W} 400 Z`} fill="#0e0f18" />
					<rect x={0} y={398} width={W} height={H - 398} fill="url(#hg_ground)" />
					{/* 草：一丛丛剪影 */}
					{Array.from({length: 60}).map((_, i) => {
						const x = rnd(i * 5) * W;
						const y = 420 + rnd(i * 3) * 280;
						const h = 8 + (y - 400) * 0.08;
						return <path key={i} d={`M ${x} ${y} l -3 ${-h} M ${x} ${y} l 2 ${-h * 1.2} M ${x} ${y} l 5 ${-h * 0.8}`} stroke="#07070a" strokeWidth={2} />;
					})}
					{/* 爪痕：从近处往远处一道道亮起来（透视越远越小） */}
					{Array.from({length: 9}).map((_, i) => {
						const t0 = 6 + i * 7;
						const a = interpolate(f, [t0, t0 + 10], [0, 1], clamp);
						const k = 1 - i * 0.1;
						const x = 640 + Math.sin(i * 0.9) * 120 * k;
						const y = 680 - i * 30;
						return (
							<g key={i} opacity={a} transform={`translate(${x} ${y}) scale(${k})`}>
								{[-14, 0, 14].map((dx) => (
									<path key={dx} d={`M ${dx - 8} -18 Q ${dx} 0 ${dx + 8} 18`} stroke="#ffb45a" strokeWidth={4} fill="none" filter="url(#glow)" />
								))}
							</g>
						);
					})}
					{/* 黑暗里睁开一只眼睛 */}
					<g transform="translate(640 350)" opacity={eye}>
						<ellipse cx={0} cy={0} rx={180} ry={70} fill="#ff9a2a" opacity={0.18} filter="url(#b26)" />
						<ellipse cx={0} cy={0} rx={70} ry={26 * eye} fill="#ffb24a" filter="url(#glow)" />
						<ellipse cx={0} cy={0} rx={8} ry={24 * eye} fill="#1a0a02" />
					</g>
				</g>
				<Motes n={30} seed={402} color="#ffcf8a" y0={380} y1={H} speed={0.3} size={2} alpha={0.6} />
			</svg>
			<div style={{position: 'absolute', left: 0, right: 0, bottom: 0, height: 280, background: 'linear-gradient(0deg, rgba(0,0,0,0.6), rgba(0,0,0,0))'}} />
			<Vignette strength={0.8} />
			<Grain amount={0.08} />
			<Fade color="#fff4e0" opacity={flash} />
			<Fade opacity={interpolate(f, [0, 6], [1, 0], clamp)} />
		</AbsoluteFill>
	);
};

// ================================================================ 灵相立绘：灵葫（替换原来那张图）
export const Gourd: React.FC = () => (
	<AbsoluteFill style={{background: '#000'}}>
		<svg width={384} height={384}>
			<Defs />
			<defs>
				<radialGradient id="gd_bg" cx="50%" cy="55%" r="70%">
					<stop offset="0%" stopColor="#3a1e08" />
					<stop offset="100%" stopColor="#050302" />
				</radialGradient>
				<radialGradient id="gd_body" cx="38%" cy="35%" r="70%">
					<stop offset="0%" stopColor="#fff0b8" />
					<stop offset="35%" stopColor="#f0a33a" />
					<stop offset="100%" stopColor="#7a3a0c" />
				</radialGradient>
			</defs>
			<rect width={384} height={384} fill="url(#gd_bg)" />
			{Array.from({length: 7}).map((_, i) => (
				<path
					key={i}
					d={`M ${192 + Math.cos(i) * 20} 200 C ${60 + i * 30} ${80 + i * 20}, ${300 - i * 20} ${40 + i * 25}, ${150 + i * 18} ${380}`}
					stroke="#ffc25a"
					strokeWidth={1.4 + (i % 3)}
					fill="none"
					opacity={0.35}
					filter="url(#b2)"
				/>
			))}
			<circle cx={192} cy={220} r={150} fill="#ffb040" opacity={0.25} filter="url(#b40)" />
			<g transform="translate(192 205) rotate(-18)">
				<ellipse cx={0} cy={48} rx={78} ry={74} fill="url(#gd_body)" />
				<ellipse cx={0} cy={-38} rx={48} ry={44} fill="url(#gd_body)" />
				<rect x={-18} y={-6} width={36} height={16} fill="#8a3e0e" />
				<rect x={-10} y={-96} width={20} height={16} rx={4} fill="#5a2a0a" />
				<path d="M -12 -2 Q -40 30 -30 70" stroke="#c0301c" strokeWidth={5} fill="none" />
				<ellipse cx={-26} cy={20} rx={16} ry={30} fill="#fff" opacity={0.25} filter="url(#b4)" />
				<path d="M 0 -96 Q 20 -150 60 -160" stroke="#fff2c0" strokeWidth={3} fill="none" filter="url(#glow)" />
			</g>
			{Array.from({length: 40}).map((_, i) => (
				<circle key={i} cx={rnd(i) * 384} cy={rnd(i * 3) * 384} r={0.8 + rnd(i * 7) * 2.2} fill="#ffe0a0" opacity={0.3 + rnd(i * 9) * 0.7} filter="url(#b1)" />
			))}
		</svg>
	</AbsoluteFill>
);
