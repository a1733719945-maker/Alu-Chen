import React from 'react';
import {Composition, Still} from 'remotion';
import {W, H} from './lib';
import {Prologue, PROLOGUE_FRAMES} from './Prologue';
import {Ascend, ASCEND_FRAMES, DungeonGate, DUNGEON_FRAMES, Gourd, HuntGate, HUNT_FRAMES, Voyage2, VOYAGE_FRAMES} from './Clips';

// 苍墟 · 猎灵 的过场动画，1280x720，30 帧/秒。渲染成 mp4 → ffmpeg 转 Ogg Theora → game/assets/cutscene/*.ogv
//   Prologue 序章 48 秒 · Voyage 渡海 8 秒 · Ascend 飞升 26 秒 · DungeonGate 进洞天 3.6 秒 · HuntGate 去猎场 4 秒
//   Gourd：灵相"灵葫"的立绘（384x384 的一张图）
export const RemotionRoot: React.FC = () => (
	<>
		<Composition id="Prologue" component={Prologue} durationInFrames={PROLOGUE_FRAMES} fps={30} width={W} height={H} />
		<Composition id="Voyage" component={Voyage2} durationInFrames={VOYAGE_FRAMES} fps={30} width={W} height={H} />
		<Composition id="Ascend" component={Ascend} durationInFrames={ASCEND_FRAMES} fps={30} width={W} height={H} />
		<Composition id="DungeonGate" component={DungeonGate} durationInFrames={DUNGEON_FRAMES} fps={30} width={W} height={H} />
		<Composition id="HuntGate" component={HuntGate} durationInFrames={HUNT_FRAMES} fps={30} width={W} height={H} />
		<Still id="Gourd" component={Gourd} width={384} height={384} />
	</>
);
