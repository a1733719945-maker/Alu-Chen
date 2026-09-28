import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame} from 'remotion';
import {BigTitle, clamp, CloudSea, Defs, easeInOut, easeOut, Fade, FloatIsland, GOLD, Grain, H, Letterbox, Motes, Narration, Pillar, rnd, SANS, SERIF, Shard, Stars, Vignette, W, win} from './lib';
import {Child, Elder, Gate, IceChi, Jiao, Kun, SpiderMother, Zhuyan} from './figures';

// 序章（48 秒）：
//   一、九重天与天门      0 ~ 210
//   二、天倾              210 ~ 420   天门裂开、崩碎，五块天枢拖着光尾坠下
//   三、苍墟              420 ~ 630   云海上一座座浮岛，大标题"苍墟"
//   四、五大灵主          630 ~ 900   五头灵兽，一头一个镜头，腹中亮着碎片
//   五、栖霞村            900 ~ 1110  湖边的村子、半塌的天坛、老猎人和醒来灵相的孩子
//   六、怎么玩 + 标题     1110 ~ 1440
export const PROLOGUE_FRAMES = 1440;

const SHARDS = ['#7dffc4', '#ff8fb0', '#ffb45a', '#8fe6ff', '#9d8cff'];

// ---------------------------------------------------------------- 一、九重天与天门
const Heavens: React.FC = () => {
	const f = useCurrentFrame();
	const tilt = interpolate(f, [0, 210], [-260, 0], {...clamp, easing: easeInOut});
	return (
		<svg width={W} height={H}>
			<Defs />
			<defs>
				<radialGradient id="h_sky" cx="50%" cy="30%" r="80%">
					<stop offset="0%" stopColor="#1d2248" />
					<stop offset="60%" stopColor="#0a0d1f" />
					<stop offset="100%" stopColor="#03040a" />
				</radialGradient>
			</defs>
			<rect width={W} height={H} fill="url(#h_sky)" />
			<g transform={`translate(0 ${tilt})`}>
				<Stars n={220} seed={11} h={H + 300} />
				{/* 九重天：九道一层比一层大的光弧 */}
				{Array.from({length: 9}).map((_, i) => {
					const r = 120 + i * 70;
					const a = 0.08 + 0.05 * Math.sin(f * 0.03 + i);
					return <ellipse key={i} cx={W / 2} cy={-40} rx={r * 1.6} ry={r * 0.55} fill="none" stroke="#bcd0ff" strokeWidth={1.2} opacity={a + 0.1} />;
				})}
				<ellipse cx={W / 2} cy={-40} rx={500} ry={200} fill="#8fa8ff" opacity={0.12} filter="url(#b40)" />
			</g>
			<g transform={`translate(0 ${tilt * 0.4})`}>
				<CloudSea y={560} color="#1a2140" light="#6d7fc0" layers={3} speed={0.6} seed={5} />
				<Gate x={W / 2} y={470} s={0.9} open={0.35 + 0.1 * Math.sin(f * 0.05)} />
				<Pillar x={W / 2} w={60} color="#ffe8b0" alpha={0.5} top={-200} bottom={440} />
			</g>
			<Motes n={40} seed={3} color="#ffe6b0" y0={200} y1={H} speed={0.4} size={2.5} alpha={0.8} />
		</svg>
	);
};

// ---------------------------------------------------------------- 二、天倾
const Fall: React.FC = () => {
	const f = useCurrentFrame() - 210;
	const crack = interpolate(f, [10, 60], [0, 1], clamp);
	const burst = interpolate(f, [60, 70, 100], [0, 1, 0], clamp);
	const gateA = interpolate(f, [62, 80], [1, 0], clamp);
	const shake = f > 50 && f < 110 ? Math.sin(f * 2.3) * interpolate(f, [50, 110], [10, 0], clamp) : 0;
	return (
		<svg width={W} height={H}>
			<Defs />
			<rect width={W} height={H} fill="#07060e" />
			<g transform={`translate(${shake} ${shake * 0.6})`}>
				<Stars n={200} seed={21} drift={0.4} />
				{/* 星河倒灌：一道道往下的光 */}
				{Array.from({length: 26}).map((_, i) => {
					const x = rnd(i * 3.3) * W;
					const len = interpolate(f, [60, 200], [0, 400 + rnd(i) * 500], clamp);
					return <line key={i} x1={x} y1={-20} x2={x - len * 0.35} y2={len} stroke="#c9d8ff" strokeWidth={1 + rnd(i) * 1.5} opacity={0.25 * interpolate(f, [60, 90], [0, 1], clamp)} />;
				})}
				<Gate x={W / 2} y={440} s={0.9} open={0.3} crack={crack} alpha={gateA} />
				{/* 门碎成的碎块往四周飞 */}
				{f > 62 &&
					Array.from({length: 40}).map((_, i) => {
						const a = rnd(i) * Math.PI * 2;
						const sp = 4 + rnd(i * 7) * 12;
						const t = f - 62;
						const x = W / 2 + Math.cos(a) * sp * t;
						const y = 400 + Math.sin(a) * sp * t + 0.12 * t * t;
						return <rect key={i} x={x} y={y} width={6 + rnd(i * 3) * 18} height={3 + rnd(i * 5) * 10} fill="#f7dfa0" opacity={interpolate(t, [0, 60], [1, 0], clamp)} transform={`rotate(${t * (rnd(i) * 20 - 10)} ${x} ${y})`} />;
					})}
				{/* 五块天枢，拖着光尾往下坠 */}
				{SHARDS.map((c, i) => {
					const t = f - 75 - i * 6;
					if (t < 0) return null;
					const sx = W / 2 + (i - 2) * 30;
					const ex = 160 + i * 240;
					const k = interpolate(t, [0, 110], [0, 1], {...clamp, easing: easeInOut});
					const x = sx + (ex - sx) * k;
					const y = 400 + 420 * k * k;
					const ang = (Math.atan2(420 * 2 * k, ex - sx) * 180) / Math.PI;
					return <Shard key={i} x={x} y={y} s={0.7} color={c} rot={t * 6} trail={120} angle={ang + 180} />;
				})}
			</g>
			<Fade color="#fff" opacity={burst * 0.85} />
		</svg>
	);
};

// ---------------------------------------------------------------- 三、苍墟：云海浮岛
const Isles: React.FC = () => {
	const f = useCurrentFrame() - 420;
	const push = interpolate(f, [0, 210], [1, 1.12], clamp);
	return (
		<svg width={W} height={H}>
			<Defs />
			<defs>
				<linearGradient id="i_sky" x1="0" y1="0" x2="0" y2="1">
					<stop offset="0%" stopColor="#1a2a55" />
					<stop offset="55%" stopColor="#c07a5c" />
					<stop offset="75%" stopColor="#f2c190" />
				</linearGradient>
			</defs>
			<rect width={W} height={H} fill="url(#i_sky)" />
			<circle cx={W * 0.7} cy={430} r={70} fill="#fff1d0" opacity={0.9} filter="url(#b6)" />
			<circle cx={W * 0.7} cy={430} r={220} fill="#ffcf8a" opacity={0.35} filter="url(#b40)" />
			<g transform={`translate(${W / 2} ${H / 2}) scale(${push}) translate(${-W / 2} ${-H / 2})`}>
				<FloatIsland x={200} y={300} s={0.45} rock="#3a2a3a" top="#4a3d52" seed={3} />
				<FloatIsland x={1060} y={250} s={0.35} rock="#3a2a3a" top="#4a3d52" seed={7} />
				<FloatIsland x={760} y={360} s={0.6} rock="#2a1f2c" top="#3a3040" seed={9} />
				<CloudSea y={470} color="#d69a86" light="#ffe0bd" layers={3} speed={0.8} seed={8} />
				<FloatIsland x={330 + f * 0.25} y={470} s={1.15} rock="#1c1420" top="#261c2c" seed={13} rim="rgba(255,200,150,0.7)" />
				<CloudSea y={600} color="#b77f74" light="#ffd6b0" layers={2} speed={1.6} seed={12} />
			</g>
			<Motes n={30} seed={9} color="#fff3d6" y0={300} y1={H} speed={0.3} size={2} alpha={0.6} />
		</svg>
	);
};

// ---------------------------------------------------------------- 四、五大灵主（一头一个镜头，背后一轮光）
const LORDS = [
	{name: '镜湖 · 碧鳞蛟', bg: ['#07211d', '#0f4a3c'], c: SHARDS[0]},
	{name: '落霞林 · 千目蛛母', bg: ['#1c0710', '#4a1024'], c: SHARDS[1]},
	{name: '苍梧林海 · 朱厌', bg: ['#1f0e05', '#5a2a0c'], c: SHARDS[2]},
	{name: '朔北冰原 · 冰螭', bg: ['#061522', '#1b4a66'], c: SHARDS[3]},
	{name: '归墟 · 玄鲲', bg: ['#02040c', '#0e1c44'], c: SHARDS[4]},
];

const Lords: React.FC = () => {
	const f = Math.max(useCurrentFrame() - 630, 0);
	const i = Math.max(0, Math.min(Math.floor(f / 54), 4));
	const t = f - i * 54;
	const L = LORDS[i];
	const zoom = interpolate(t, [0, 54], [1.08, 1.0], clamp);
	const a = win(t, 0, 54, 8, 8);
	return (
		<svg width={W} height={H}>
			<Defs />
			<defs>
				<radialGradient id={`l_bg${i}`} cx="55%" cy="42%" r="70%">
					<stop offset="0%" stopColor={L.bg[1]} />
					<stop offset="100%" stopColor={L.bg[0]} />
				</radialGradient>
			</defs>
			<rect width={W} height={H} fill={`url(#l_bg${i})`} />
			<g opacity={a} transform={`translate(${W / 2} ${H / 2}) scale(${zoom}) translate(${-W / 2} ${-H / 2})`}>
				<circle cx={W * 0.55} cy={300} r={230} fill={L.c} opacity={0.18} filter="url(#b40)" />
				<Stars n={60} seed={40 + i} alpha={0.4} />
				{i === 0 && (
					<>
						<Jiao x={640} y={330} s={1.05} shard={L.c} />
						<rect x={0} y={560} width={W} height={200} fill="#041512" opacity={0.85} />
					</>
				)}
				{i === 1 && (
					<>
						{Array.from({length: 12}).map((_, k) => (
							<line key={k} x1={640} y1={300} x2={640 + Math.cos(k * 0.52) * 900} y2={300 + Math.sin(k * 0.52) * 900} stroke="#ffc0d0" strokeWidth={0.8} opacity={0.25} />
						))}
						{[120, 200, 290, 390].map((r) => (
							<circle key={r} cx={640} cy={300} r={r} fill="none" stroke="#ffc0d0" strokeWidth={0.8} opacity={0.2} />
						))}
						<SpiderMother x={640} y={330} s={1.0} shard={L.c} />
					</>
				)}
				{i === 2 && <Zhuyan x={640} y={330} s={1.05} shard={L.c} />}
				{i === 3 && (
					<>
						<IceChi x={640} y={330} s={1.1} shard={L.c} />
						<Motes n={80} seed={77} color="#e8fbff" y0={0} y1={H} speed={-1.2} size={2.2} />
					</>
				)}
				{i === 4 && (
					<>
						{Array.from({length: 7}).map((_, k) => (
							<path key={k} d={`M ${200 + k * 160} -20 L ${120 + k * 160} ${H} L ${260 + k * 160} ${H} Z`} fill="#8fb8ff" opacity={0.05} filter="url(#b16)" />
						))}
						<Kun x={690} y={360} s={0.95} shard={L.c} />
					</>
				)}
			</g>
			<g opacity={a}>
				<text x={96} y={140} fill={L.c} fontFamily={SANS} fontSize={18} letterSpacing={8} fontWeight={700}>
					{['其一', '其二', '其三', '其四', '其五'][i]}
				</text>
				<text x={96} y={188} fill="#f4ecd8" fontFamily={SERIF} fontSize={40} letterSpacing={10} fontWeight={900}>
					{L.name}
				</text>
				<line x1={96} y1={204} x2={96 + 60 + t * 4} y2={204} stroke={L.c} strokeWidth={2} />
			</g>
		</svg>
	);
};

// ---------------------------------------------------------------- 五、栖霞村
const Village: React.FC = () => {
	const f = useCurrentFrame() - 900;
	const wake = interpolate(f, [70, 150], [0, 1], clamp);
	return (
		<svg width={W} height={H}>
			<Defs />
			<defs>
				<linearGradient id="v_sky" x1="0" y1="0" x2="0" y2="1">
					<stop offset="0%" stopColor="#141a36" />
					<stop offset="50%" stopColor="#6a3f55" />
					<stop offset="68%" stopColor="#e39a6a" />
				</linearGradient>
				<linearGradient id="v_lake" x1="0" y1="0" x2="0" y2="1">
					<stop offset="0%" stopColor="#c98262" />
					<stop offset="100%" stopColor="#1a1426" />
				</linearGradient>
			</defs>
			<rect width={W} height={H} fill="url(#v_sky)" />
			<Stars n={80} seed={61} alpha={0.5} h={300} />
			{/* 远山 */}
			<path d={`M 0 430 ${Array.from({length: 17}).map((_, i) => `L ${i * 80} ${380 - rnd(i + 5) * 70}`).join(' ')} L ${W} 430 Z`} fill="#3a2a40" opacity={0.9} />
			<path d={`M 0 450 ${Array.from({length: 22}).map((_, i) => `L ${i * 62} ${415 - rnd(i + 9) * 40}`).join(' ')} L ${W} 450 Z`} fill="#281d30" />
			{/* 湖 */}
			<rect x={0} y={450} width={W} height={H - 450} fill="url(#v_lake)" />
			{Array.from({length: 14}).map((_, i) => (
				<rect key={i} x={rnd(i) * W} y={470 + i * 16} width={60 + rnd(i * 3) * 160} height={1.4} fill="#ffd0a0" opacity={0.25 + 0.15 * Math.sin(f * 0.06 + i)} />
			))}
			{/* 村子：一排屋顶，窗子亮着灯 */}
			{Array.from({length: 9}).map((_, i) => {
				const x = 40 + i * 70;
				const h = 34 + rnd(i * 4) * 20;
				return (
					<g key={i}>
						<rect x={x} y={450 - h} width={54} height={h} fill="#150f14" />
						<path d={`M ${x - 10} ${450 - h} L ${x + 27} ${450 - h - 22} L ${x + 64} ${450 - h} Z`} fill="#150f14" />
						<rect x={x + 18} y={450 - h + 12} width={10} height={9} fill="#ffc46a" opacity={0.6 + 0.4 * Math.sin(f * 0.1 + i)} />
					</g>
				);
			})}
			{/* 半塌的古天坛：一圈石台、几根断柱 */}
			<g transform="translate(900 470)">
				<ellipse cx={0} cy={0} rx={190} ry={30} fill="#1a1216" />
				<ellipse cx={0} cy={-10} rx={160} ry={22} fill="#241a20" stroke="#e8b27a" strokeWidth={1} opacity={0.9} />
				{[-130, -70, 60, 125].map((x, i) => (
					<rect key={i} x={x - 9} y={-10 - (i === 1 ? 50 : 110)} width={18} height={i === 1 ? 50 : 110} fill="#1a1216" stroke="#e8b27a" strokeWidth={0.8} />
				))}
				<Elder x={-40} y={-12} s={1.0} />
				<Child x={40} y={-12} s={1.0} />
				{/* 孩子醒来灵相：脚下一圈光，一道光往上 */}
				<g opacity={wake}>
					<ellipse cx={40} cy={-12} rx={60 * wake} ry={12 * wake} fill="none" stroke="#9fd8ff" strokeWidth={2} filter="url(#glow)" />
					<Pillar x={40} w={26} color="#a8dcff" alpha={wake * 0.9} top={-700} bottom={-10} />
				</g>
			</g>
			<Motes n={60} seed={31} color="#fff0a0" y0={380} y1={H} speed={0.35} size={2.4} alpha={0.9} />
		</svg>
	);
};

// ---------------------------------------------------------------- 六、怎么玩
const STEPS = [
	{k: '一', t: '猎灵', d: '按 L 打开猎灵榜挑一只灵兽 → 去猎场循着爪痕追它 → 击杀或活捉 → 炼化它的灵环。猎哪一只，决定你悟出哪门神通'},
	{k: '二', t: '破境', d: '炼气、筑基、金丹、元婴……每十级一个大境界，门槛上要炼化一枚灵环，年份一环比一环高'},
	{k: '三', t: '洞天', d: '地图上的「秘」是天倾时坠下的洞天碎片：一波波灵兽、一位秘境之主，刷修为、寻灵骨'},
	{k: '四', t: '叩天', d: '境界够了，去古天坛叩天，逼出本岛的灵主。打倒它，夺回一块天枢碎片，坐船去下一座岛'},
];

const HowTo: React.FC = () => {
	const f = useCurrentFrame() - 1110;
	return (
		<svg width={W} height={H}>
			<Defs />
			<defs>
				<radialGradient id="ht_bg" cx="50%" cy="40%" r="80%">
					<stop offset="0%" stopColor="#16203a" />
					<stop offset="100%" stopColor="#05070e" />
				</radialGradient>
			</defs>
			<rect width={W} height={H} fill="url(#ht_bg)" />
			<Stars n={120} seed={91} alpha={0.45} />
			<Motes n={30} seed={92} color="#f2cf7a" y0={0} y1={H} speed={0.25} size={2} alpha={0.5} />
		</svg>
	);
};

const HowToText: React.FC = () => {
	const f = useCurrentFrame() - 1110;
	const out = interpolate(f, [236, 256], [1, 0], clamp);
	return (
		<div style={{position: 'absolute', left: 150, right: 150, top: 78, opacity: out}}>
			<div style={{fontFamily: SANS, fontSize: 16, letterSpacing: 10, color: GOLD, fontWeight: 700, opacity: win(f, 0, 400, 14, 14)}}>修行之道</div>
			{STEPS.map((s, i) => {
				const t0 = 12 + i * 44;
				const a = interpolate(f, [t0, t0 + 16], [0, 1], clamp);
				const x = interpolate(f, [t0, t0 + 22], [-30, 0], {...clamp, easing: easeOut});
				return (
					<div key={i} style={{display: 'flex', alignItems: 'flex-start', gap: 26, marginTop: 22, opacity: a, transform: `translateX(${x}px)`}}>
						<div style={{fontFamily: SERIF, fontWeight: 900, fontSize: 46, color: GOLD, width: 60, textAlign: 'center', lineHeight: 1, filter: 'drop-shadow(0 0 12px rgba(242,207,122,0.5))'}}>{s.k}</div>
						<div>
							<div style={{fontFamily: SERIF, fontWeight: 900, fontSize: 32, color: '#f6eedb', letterSpacing: 8}}>{s.t}</div>
							<div style={{fontFamily: SANS, fontWeight: 400, fontSize: 19, color: 'rgba(230,226,215,0.86)', marginTop: 6, lineHeight: 1.55}}>{s.d}</div>
						</div>
					</div>
				);
			})}
			<div
				style={{
					marginTop: 26,
					paddingTop: 14,
					borderTop: '1px solid rgba(242,207,122,0.35)',
					fontFamily: SANS,
					fontSize: 17,
					color: 'rgba(230,226,215,0.8)',
					letterSpacing: 2,
					opacity: interpolate(f, [186, 204], [0, 1], clamp),
				}}
			>
				WASD 移动 · 左键 暗器 · 右键 瞄准 · Q / E / F 神通 · G 引魂索 · Ctrl 翻滚：贴着攻击滚过去是「极限闪避」
			</div>
		</div>
	);
};

export const Prologue: React.FC = () => {
	const f = useCurrentFrame();
	const scenes: [number, number, React.ReactNode][] = [
		[0, 214, <Heavens key="a" />],
		[206, 424, <Fall key="b" />],
		[416, 634, <Isles key="c" />],
		[626, 904, <Lords key="d" />],
		[896, 1114, <Village key="e" />],
		[1106, 1440, <HowTo key="f" />],
	];
	return (
		<AbsoluteFill style={{background: '#000'}}>
			{scenes.map(([a, b, node], i) =>
				f >= a && f <= b ? (
					<AbsoluteFill key={i} style={{opacity: win(f, a, b, 10, 10)}}>
						{node}
					</AbsoluteFill>
				) : null,
			)}
			{/* 旁白 */}
			<Narration text="上古之时，天有九重。" from={24} to={112} />
			<Narration text="人间与九天之间，立着一座天门。" from={112} to={204} />
			<Narration text="三万年前——天倾。" from={228} to={300} size={38} />
			<Narration text="天门崩碎，天枢裂为五块，坠入人间。" from={302} to={412} />
			<Narration text="大地沉入云海，只剩一座座孤岛。" from={436} to={536} />
			<Narration text="后人把这片破碎的大地，叫作——" from={536} to={596} />
			<BigTitle text="苍墟" from={584} to={632} size={150} y={220} />
			<Narration text="五块碎片，被五头上古灵兽吞下——它们成了不死的灵主。" from={640} to={766} y={600} size={28} />
			<Narration text="碎片的灵气日夜外溢。兽潮，一次比一次来得早。" from={770} to={896} y={600} size={28} />
			<Narration text="「三万年没人飞升，不是天太高——是门碎了。」" from={912} to={1004} size={30} color="#ffe2b8" />
			<Narration text="「去猎灵，去炼环，把境界一层一层冲上去。」" from={1004} to={1058} size={30} color="#ffe2b8" />
			<Narration text="「五块碎片凑齐那天，天门重开——你也就飞升了。」" from={1058} to={1112} size={30} color="#ffe2b8" />
			{f >= 1106 && <HowToText />}
			<BigTitle text="苍墟 · 猎灵" from={1366} to={1440} size={96} y={250} sub="猎灵 · 炼环 · 破境 · 叩天" />
			<Vignette strength={0.7} />
			<Grain amount={0.08} />
			<Letterbox h={48} />
			<Fade opacity={interpolate(f, [0, 20], [1, 0], clamp) + interpolate(f, [1425, 1440], [0, 1], clamp)} />
		</AbsoluteFill>
	);
};
