import React from 'react';
import {Composition, Still} from 'remotion';
import {FPS, H, W} from './cine';
import {Ascend, ASCEND_FRAMES, DungeonGate, DUNGEON_FRAMES, HuntGate, HUNT_FRAMES, Prologue, PROLOGUE_FRAMES, Voyage, VOYAGE_FRAMES} from './Films';
import {CNTest, CNTEST_FRAMES} from './FilmsCN';
import {Gourd} from './Gourd';

// 苍墟 · 猎灵 的过场动画，1920x1080，30 帧/秒。render_all.sh 渲染成 mp4 → ffmpeg 转 Ogg Theora → game/assets/cutscene/*.ogv
//   Prologue 序章 48 秒 · Voyage1~5 渡海到第 N 章 8 秒 · Ascend 飞升 26 秒 · DungeonGate 进洞天 3.6 秒 · HuntGate 去猎场 4 秒
//   Gourd：灵相"灵葫"的立绘（384x384 的一张图）
export const RemotionRoot: React.FC = () => (
	<>
		<Composition id="Prologue" component={Prologue} durationInFrames={PROLOGUE_FRAMES} fps={FPS} width={W} height={H} />
		{[1, 2, 3, 4, 5].map((ch) => (
			<Composition key={ch} id={`Voyage${ch}`} component={Voyage} defaultProps={{ch}} durationInFrames={VOYAGE_FRAMES} fps={FPS} width={W} height={H} />
		))}
		<Composition id="Ascend" component={Ascend} durationInFrames={ASCEND_FRAMES} fps={FPS} width={W} height={H} />
		<Composition id="DungeonGate" component={DungeonGate} durationInFrames={DUNGEON_FRAMES} fps={FPS} width={W} height={H} />
		<Composition id="HuntGate" component={HuntGate} durationInFrames={HUNT_FRAMES} fps={FPS} width={W} height={H} />
		<Composition id="CNTest" component={CNTest} durationInFrames={CNTEST_FRAMES} fps={FPS} width={W} height={H} />
		<Still id="Gourd" component={Gourd} width={384} height={384} />
	</>
);
