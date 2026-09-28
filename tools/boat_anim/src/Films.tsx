import React from 'react';
import {BigStat, Film, Flash, Label, PaperCard, ShardFall, Shot, Sub, Title} from './cine';

// 苍墟 · 猎灵 的过场动画：画面全是公有领域的名画（清单和出处见 art.json），慢推镜头 + 调色 + 双语字幕。
// 帧数都是 30 帧/秒。

// ================================================================ 序章（48 秒）
//   一、九重天与天门   科尔《人生的旅程 · 青年》里云中的宫殿
//   二、天倾           约翰 · 马丁《天怒之日》+ 五块天枢坠下
//   三、苍墟           弗里德里希《雾海上的旅人》
//   四、五大灵主       五座岛各一张快切 → 多雷《毁灭利维坦》→ 博纳尔《马市》（兽潮）
//   五、栖霞村         弗里德里希《两人望月》（青崖子）→ 丘奇《安第斯之心》→ 天门
//   六、怎么玩 + 标题  弗里德里希《海边的修士》+ 纸片卡片 → 丘奇《荒野暮光》
export const PROLOGUE_FRAMES = 1440;

const LORDS: {art: 'merced' | 'twilight' | 'pineforest' | 'seaofice' | 'ninthwave'; n: string; name: string; a: [number, number, number]; b: [number, number, number]}[] = [
	{art: 'merced', n: '其一', name: '碧鳞蛟 · 镜湖', a: [0.5, 0.55, 1.25], b: [0.52, 0.52, 1.36]},
	{art: 'twilight', n: '其二', name: '千目蛛母 · 落霞林', a: [0.45, 0.5, 1.3], b: [0.5, 0.48, 1.42]},
	{art: 'pineforest', n: '其三', name: '朱厌 · 苍梧林海', a: [0.5, 0.6, 1.3], b: [0.46, 0.64, 1.45]},
	{art: 'seaofice', n: '其四', name: '冰螭 · 朔北冰原', a: [0.5, 0.5, 1.25], b: [0.5, 0.46, 1.36]},
	{art: 'ninthwave', n: '其五', name: '玄鲲 · 归墟', a: [0.55, 0.45, 1.2], b: [0.6, 0.42, 1.34]},
];

export const Prologue: React.FC = () => (
	<Film total={PROLOGUE_FRAMES} fadeIn={24} fadeOut={16}>
		{/* 一、九重天与天门 */}
		<Shot art="youth" from={0} to={224} fadeIn={0} fadeOut={0} a={[0.42, 0.46, 1.08]} b={[0.26, 0.3, 1.5]} fx="dust" glow={{x: 0.19, y: 0.2, r: 260, color: 'rgba(255,236,200,1)', a: 0.16}} />
		<Label top="太 初" sub="九重天 · 天门" from={20} to={204} />
		<Sub zh="上古之时，天有九重。" en="In the beginning, the heavens rose in nine tiers." from={26} to={110} />
		<Sub zh="人间与九天之间，立着一座天门。" en="Between the mortal world and the heavens stood a single gate." from={116} to={206} />

		{/* 二、天倾 */}
		<Shot art="wrath" from={210} to={434} fadeIn={8} fadeOut={0} a={[0.28, 0.42, 1.3]} b={[0.64, 0.5, 1.12]} fx="embers" shake={[212, 262, 12]} grade={{warm: 0.3, con: 1.1}} />
		<Flash at={210} len={26} />
		<ShardFall from={300} />
		<Label top="三万年前" sub="天 倾" from={226} to={414} />
		<Sub zh="三万年前——天倾。" en="Thirty thousand years ago, the sky fell." from={230} to={300} />
		<Sub zh="天门崩碎，天枢裂为五块，坠入人间。" en="The gate shattered. Its keystone split in five and fell to earth." from={304} to={414} />

		{/* 三、苍墟 */}
		<Shot art="wanderer" from={416} to={652} fadeIn={20} fadeOut={0} a={[0.52, 0.68, 1.2]} b={[0.5, 0.3, 1.0]} fx="mist" grade={{warm: 0.12}} />
		<Label top="天倾之后" sub="云海 · 孤岛" from={440} to={574} />
		<Sub zh="大地沉入云海，只剩一座座孤岛。" en="The land sank beneath a sea of cloud. Only islands remained." from={438} to={532} />
		<Sub zh="后人把这片破碎的大地，叫作——" en="Those who came after gave the broken world a name —" from={536} to={590} />
		<Title zh="苍墟" en="CANGXU  ·  THE SHATTERED EARTH" from={586} to={648} size={170} />

		{/* 四、五大灵主：五座岛快切 */}
		{LORDS.map((l, i) => {
			const a = 648 + i * 28;
			const last = i === LORDS.length - 1;
			return (
				<React.Fragment key={l.art}>
					<Shot art={l.art} from={a} to={last ? a + 44 : a + 34} fadeIn={i === 0 ? 10 : 6} fadeOut={0} a={l.a} b={l.b} fx={l.art === 'seaofice' ? 'snow' : 'dust'} />
					<Label top={`灵主 · ${l.n}`} sub={l.name} from={a + 2} to={a + 30} fade={6} />
				</React.Fragment>
			);
		})}
		<Sub zh="五块碎片，被五头上古灵兽吞下——它们成了不死的灵主。" en="Five ancient beasts swallowed the shards — and became the undying Spirit Lords." from={650} to={782} />
		<Shot art="leviathan" from={784} to={862} fadeIn={8} fadeOut={0} a={[0.42, 0.68, 1.35]} b={[0.4, 0.6, 1.55]} grade={{sepia: 0.45, con: 1.12, warm: 0.3}} fx="dust" shake={[786, 806, 5]} />
		<Sub zh="碎片的灵气日夜外溢。" en="The shards bleed power, day and night." from={788} to={852} />
		<Shot art="horsefair" from={854} to={914} fadeIn={8} fadeOut={0} a={[0.3, 0.55, 1.15]} b={[0.56, 0.55, 1.2]} fx="dust" />
		<Label top="如 今" sub="兽 潮" from={860} to={906} />
		<Sub zh="兽潮，一次比一次来得早。" en="And every beast tide comes sooner than the last." from={858} to={906} />

		{/* 五、栖霞村 · 青崖子 */}
		<Shot art="twomen" from={908} to={1012} fadeIn={12} fadeOut={0} a={[0.46, 0.5, 1.12]} b={[0.4, 0.5, 1.3]} fx="dust" />
		<Label top="栖霞村" sub="老猎人 · 青崖子" from={914} to={1000} />
		<BigStat value={30000} unit="年 · 无人飞升" from={926} to={1002} />
		<Sub quote zh="「三万年没人飞升，不是天太高——是门碎了。」" en="“No one has ascended in thirty thousand years. The sky isn't too high — the gate is broken.”" from={914} to={1004} />
		<Shot art="heartandes" from={1000} to={1066} fadeIn={10} fadeOut={0} a={[0.3, 0.5, 1.15]} b={[0.62, 0.5, 1.18]} fx="mist" />
		<Sub quote zh="「去猎灵，去炼环，把境界一层一层冲上去。」" en="“Go hunt. Forge your rings. Break through, one realm at a time.”" from={1008} to={1058} />
		<Shot art="youth" from={1056} to={1120} fadeIn={10} fadeOut={0} a={[0.26, 0.28, 1.45]} b={[0.24, 0.26, 1.58]} fx="dust" grade={{bri: 0.88, con: 1.12}} glow={{x: 0.19, y: 0.2, r: 300, color: 'rgba(255,236,200,1)', a: 0.14}} />
		<Sub quote zh="「五块碎片凑齐那天，天门重开——你也就飞升了。」" en="“Bring the five shards home, and the gate will open. That day, you ascend.”" from={1062} to={1112} />

		{/* 六、怎么玩 */}
		<Shot art="monk" from={1114} to={1382} fadeIn={16} fadeOut={0} a={[0.42, 0.56, 1.05]} b={[0.36, 0.6, 1.14]} fx="mist" grade={{bri: 0.86, warm: 0.16}} />
		<PaperCard
			from={1124}
			to={1368}
			headEn="THE PATH OF THE HUNTER"
			head="修行之道"
			rows={[
				{key: 'L', title: '猎灵', desc: '猎灵榜挑一只灵兽，去猎场循着爪痕追它。它的灵环，决定你悟出哪门神通', bar: 0.9},
				{key: '境', title: '破境', desc: '每十级一个大境界，门槛上要炼化一枚灵环', bar: 0.7},
				{key: '秘', title: '洞天', desc: '地图上的「秘」：一波波灵兽和秘境之主，刷修为、寻灵骨', bar: 0.55},
				{key: '天', title: '叩天', desc: '去古天坛逼出灵主，夺回天枢碎片，坐船去下一座岛', bar: 1.0},
			]}
			foot="WASD 移动 · 左键 暗器 · 右键 瞄准 · QEF 神通 · G 引魂索 · Ctrl 翻滚"
		/>

		{/* 标题 */}
		<Shot art="twilight" from={1370} to={1440} fadeIn={14} fadeOut={0} a={[0.5, 0.42, 1.2]} b={[0.5, 0.45, 1.06]} fx="dust" />
		<Title zh="苍墟 · 猎灵" kicker="猎灵 · 炼环 · 破境 · 叩天" en="HUNT  ·  FORGE  ·  ASCEND" from={1376} to={1440} size={124} />
	</Film>
);

// ================================================================ 渡海（每章一段，8 秒）：月下出海 → 目的地
export const VOYAGE_FRAMES = 240;
type Dest = {art: 'merced' | 'twilight' | 'pineforest' | 'seaofice' | 'ninthwave'; kicker: string; name: string; en: string; story: string; storyEn: string; a: [number, number, number]; b: [number, number, number]; fx: 'dust' | 'mist' | 'snow'};
export const DESTS: Record<number, Dest> = {
	1: {art: 'merced', kicker: '前往 · 第一章', name: '镜湖', en: 'MIRROR LAKE', story: '栖霞村外，镜湖。碧鳞蛟吞下第一块天枢碎片，三千年未曾离湖。', storyEn: 'Mirror Lake, beyond Qixia. The Jade Serpent swallowed the first shard, and has not left the water in three thousand years.', a: [0.5, 0.6, 1.25], b: [0.52, 0.5, 1.05], fx: 'mist'},
	2: {art: 'twilight', kicker: '前往 · 第二章', name: '落霞林', en: 'THE SUNSET WOOD', story: '落霞林，永远停在黄昏。千目蛛母的丝，织满了整片林子。', storyEn: 'The Sunset Wood, forever at dusk. The Thousand-Eyed Mother has woven the whole forest in silk.', a: [0.42, 0.52, 1.3], b: [0.5, 0.46, 1.05], fx: 'dust'},
	3: {art: 'pineforest', kicker: '前往 · 第三章', name: '苍梧林海', en: 'THE CANGWU FOREST SEA', story: '苍梧林海。朱厌一睁眼，天下便起刀兵——它已经开始醒了。', storyEn: 'The Cangwu Forest Sea. When Zhuyan opens its eyes, war follows — and it is already stirring.', a: [0.5, 0.5, 1.05], b: [0.45, 0.62, 1.35], fx: 'mist'},
	4: {art: 'seaofice', kicker: '前往 · 第四章', name: '朔北冰原', en: 'THE NORTHERN ICEFIELD', story: '朔北冰原，终年不见日。冰螭呼一口气，一整片海就冻成了冰。', storyEn: 'The Northern Icefield, where the sun never rises. One breath of the Ice Chi froze an entire sea.', a: [0.5, 0.56, 1.3], b: [0.5, 0.46, 1.05], fx: 'snow'},
	5: {art: 'ninthwave', kicker: '前往 · 第五章', name: '归墟', en: 'GUIXU  ·  WHERE ALL WATERS END', story: '归墟，众水归处。北冥有鱼，其名为鲲——最后一块碎片，在它腹中。', storyEn: 'Guixu, where all waters end. In the northern dark lives a fish called Kun — and the last shard lies within it.', a: [0.4, 0.62, 1.12], b: [0.52, 0.56, 1.02], fx: 'dust'},
};

export const Voyage: React.FC<{ch: number}> = ({ch}) => {
	const d = DESTS[ch] ?? DESTS[2];
	return (
		<Film total={VOYAGE_FRAMES} fadeIn={14} fadeOut={14}>
			<Shot art="moonrise" from={0} to={108} fadeIn={0} fadeOut={0} a={[0.5, 0.52, 1.12]} b={[0.42, 0.47, 1.32]} fx="mist" grade={{warm: 0.14}} />
			<Label top="渡 海" sub="苍墟云海" from={8} to={96} />
			<Shot art={d.art} from={92} to={240} fadeIn={18} fadeOut={0} a={d.a} b={d.b} fx={d.fx} grade={d.art === 'seaofice' ? {warm: 0.06, sat: 0.85} : undefined} />
			<Title zh={d.name} kicker={d.kicker} en={d.en} from={108} to={236} size={120} y={-70} />
			<Sub zh={d.story} en={d.storyEn} from={130} to={236} />
		</Film>
	);
};

// ================================================================ 进洞天秘境（3.6 秒）：皮拉内西《幻想监狱》，往黑处推进去
export const DUNGEON_FRAMES = 108;
export const DungeonGate: React.FC = () => (
	<Film total={DUNGEON_FRAMES} fadeIn={8} fadeOut={22}>
		<Shot art="drawbridge" from={0} to={108} fadeIn={0} fadeOut={0} a={[0.5, 0.58, 1.0]} b={[0.5, 0.5, 1.4]} fx="dust" grade={{sepia: 0.65, bri: 0.78, con: 1.18, warm: 0.32, sat: 1.0}} />
	</Film>
);

// ================================================================ 去猎场（4 秒）：比尔施塔特《内华达山脉之间》，推向湖边的鹿
export const HUNT_FRAMES = 120;
export const HuntGate: React.FC = () => (
	<Film total={HUNT_FRAMES} fadeIn={8} fadeOut={22}>
		<Shot art="sierra" from={0} to={120} fadeIn={0} fadeOut={0} a={[0.5, 0.48, 1.02]} b={[0.56, 0.64, 1.38]} fx="mist" />
	</Film>
);

// ================================================================ 飞升（26 秒）：碎片归位 → 天门开 → 光里 → 九重天 → 第一重 → 轮回
export const ASCEND_FRAMES = 780;
export const Ascend: React.FC = () => (
	<Film total={ASCEND_FRAMES} fadeIn={20} fadeOut={20}>
		<Shot art="youth" from={0} to={186} fadeIn={0} fadeOut={0} a={[0.38, 0.42, 1.1]} b={[0.25, 0.28, 1.55]} fx="dust" grade={{bri: 0.9, con: 1.1}} glow={{x: 0.19, y: 0.2, r: 300, color: 'rgba(255,240,205,1)', a: 0.2}} />
		<Sub zh="五块天枢，归位。" en="The five shards return to their place." from={30} to={132} />
		<Flash at={150} len={30} max={0.7} />
		<Sub zh="天门，重开。" en="The gate opens." from={156} to={252} />
		<Shot art="oldage" from={172} to={452} fadeIn={16} fadeOut={0} a={[0.55, 0.72, 1.3]} b={[0.28, 0.28, 1.25]} fx="dust" glow={{x: 0.2, y: 0.15, r: 460, color: 'rgba(255,236,196,1)', a: 0.32}} />
		<Sub zh="灵气归天，万兽安驯。" en="Power flows back to the heavens. The beasts grow calm." from={262} to={340} />
		<Sub zh="你踏进了光里——" en="You step into the light —" from={346} to={436} />
		<Flash at={440} len={32} max={0.9} />
		<Shot art="lightcolour" from={442} to={660} fadeIn={10} fadeOut={0} a={[0.5, 0.48, 1.0]} b={[0.5, 0.48, 1.38]} fx="dust" grade={{warm: 0.26}} />
		<Label top="九重天" sub="一层叠一层" from={470} to={640} />
		<Sub zh="可门后不是天。" en="But beyond the gate, there is no sky." from={452} to={540} />
		<Sub zh="是九重天。一层叠一层，每一重都塌着。" en="Only the Nine Heavens — tier upon tier, and every one of them fallen." from={544} to={644} />
		<Shot art="wanderer" from={650} to={722} fadeIn={12} fadeOut={0} a={[0.5, 0.3, 1.0]} b={[0.5, 0.33, 1.1]} fx="mist" grade={{warm: 0.12}} />
		<Sub quote zh="你站着的，只是第一重。" en="Where you stand is only the first." from={654} to={716} />
		<Shot art="childhood" from={714} to={780} fadeIn={14} fadeOut={0} a={[0.45, 0.55, 1.25]} b={[0.45, 0.55, 1.1]} fx="dust" />
		<Title zh="轮回" kicker="第二重天" en="SAMSARA  ·  THE SECOND HEAVEN" from={718} to={780} size={160} />
	</Film>
);
