
/*
State(\mass).doInit();
State(\mass).doStart();
State(\mass).doStop();
*/

/////////////////////////////////////////////////////////////////////////////////

LogWindow(\mass, [\LCDevice, \mass, \error]).front;
State(\mass).clear;
State(\mass).push;
State(\mass).autoEnvirWindow = true;

State(\mass).initActions.add({

	/////////////////////////////////////////////////////////////////////////////////
	// SYNTHDEFS
	/////////////////////////////////////////////////////////////////////////////////

	(
		~voiceCount = 60;
		~scale = Scale.dorian;
		~chordSequence = {
			|count, base|
			[
				[[  1, 4, 6     ],		[0, 1]		],
				[[  3, 5, 8     ],		[0, 1]		],
				[[  0, 3, 7, 11 ],		[0, 1]		],
				[[  1, 5, 10    ],		[0, 1] + 1	],
				[[ -3, 1, 6, 13 ],		[0, 1] + 1	],
				[[  2, 6, 13    ],		[0, 1] + 1	],
				[[  2, 4, 6, 13 ],		[0, 1, 2]	],
				[[ -1, 3, 8, 15 ],		[0, 1, 2]	]
			].collect {
				|chord|
				count.collect {
					|i|
					var iter = chord.reverse.allTuples.wrapAt(i).reverse;
					~scale.degreeToFreq(iter[0], base.midicps, iter[1]);
				};
			}
		};
		~chordSequenceLow 	= ~chordSequence.(~voiceCount , 30);
		~chordSequenceHigh 	= ~chordSequence.(~voiceCount , 30 + 24);

		~massDef = {
			|name, lesser=true|

			SynthDef((\mass ++ "." ++ name).asSymbol, {
				var pulse, pulse2, phase, noise, noise2, jumps, phases, density, distAmt,
				pulseAmt, freqFade, sig, freqs, freqMult, fx, clip, filtSig, volume,
				bSig, cut, densityMult;

				////////////////////////////////////////////////////////////////
				// CONTROLS
				density 	= \density.kr(0).lag(5);
				fx 			= \fx.kr(0).lag3(5);
				clip 		= \clip.kr(5).lag(8);
				distAmt		= \distAmt.kr(0);
				densityMult = lesser.if(1, 10);

				////////////////////////////////////////////////////////////////
				// CONTROLS
				phase = LFNoise2.kr(0.1).range(0.06, 0.09);
				pulse = (
					(Impulse.ar(3) * WhiteNoise.ar(2))
					+ (Impulse.ar(1, phase) * WhiteNoise.ar(2))
					+ (Impulse.ar(6, phase) * WhiteNoise.ar(1))
				);

				jumps = 2.collect({
					PanAz.ar(
						~voiceCount, pulse,
						pos: LFNoise2.kr(0.06).range(-1,1),
						width: LFNoise2.kr(0.07).range(
							2 + (density * densityMult),
							2 + (density * densityMult * 4)   // greater was *2?
						)
					)
				}).sum;
				jumps.assertChannels(~voiceCount);

				jumps = jumps * EnvGen.kr(Env([0, 0, 1, 1], [4, 4, 20]), timeScale:5);
				phases = jumps.collect({
					| jump |
					(2.0.rand + Integrator.ar(jump.abs.neg * 0.2, 1)) % (2 * pi);
				});

				pulseAmt = LFNoise2.kr(LFNoise2.kr(0.1).range(0.05, 0.2)).exprange(0.5, 1.0);
				// pulseAmt = LFNoise2.kr(LFNoise2.kr(0.2).range(0.1, 0.3)).exprange(0.5, 2.0); // greater

				freqs = phases.collect({
					| p, i |
					Select.kr(fx + Rand(-0.35, 0.5), ~chordSequenceLow.flop[i]);
				});

				noise = phases.collect({
					| phase, i |
					var sig, degree, freq, freq1, freq2, saw, hpEnv, scale, bump;
					if (lesser) {
						hpEnv = max(0, SinOsc.kr(1 / 100, phase.lag(0.1)).abs - density.linlin(0, 1, 0.55, 0.42)).lag(0.2);
					} {
						hpEnv = max(0, SinOsc.kr(0.007, phase.lag(0.2)).abs - density.exprange(0.9, 0.22)); // greater
					};
					freq = freqs[i];

					if (i < 40) {
						freq = freq * (density.linlin(0, 1, 1.0, 1 + Rand(-0.02, 0.02)) + [0.03.rand, 0.02.rand, 0.04.rand]);
						saw = LFSaw.ar(freq).sum * density.linlin(0, 1, 0.55, 1.0) * [-1, 1].choose;
						// greater
						// freq = freq * (density.range(1.0, 1.01) + [0.03.rand, 0.02.rand, 0.04.rand]);
						// saw = LFSaw.ar(freq).sum * density.range(0.2, 1.0);
					} {
						freq = freq * (density.linlin(0, 1, 1.0, Rand(-0.03, 0.03)) + [0.015.rand, 0.01.rand, 0.021.rand]);
						saw = LFPulse.ar(freq, 0, density.linlin(0, 1, 0, 0.99)).sum * max(density - 0.5, 0) * [-1, 1].choose;
						// greater
						// freq = freq * (density.range(1, 1) + [0.03.rand, 0.01.rand, 0.02.rand]);
						// saw = LFSaw.ar(freq).sum * max(density - 0.5, 0);
					};

					sig = saw;

					if (lesser) {
						sig = sig + (BrownNoise.ar(0.5 + density.linlin(0, 1, 0, 0.5)) * sig);
						sig = sig * hpEnv;

						sig = LPF.ar(sig, max(density.linexp(0, 1, 10, 16000) * hpEnv, 20));

						filtSig = (
							HPF.ar(sig, clip.range(500, 18000), mul: clip.range(1, 4.0))
							+ LPF.ar(sig, clip.range(20000, 40), mul:0)
						);
						sig = XFade2.ar(sig, filtSig, clip.range(-1, 1));

						sig = sig * LPF.ar(
							in: LFPulse.ar(
								freq: 	[20, 30, 60].choose,
								iphase:	[0, 0.25, 0.5, 0.75, 1].wrapAt(i),
								width:	LFDNoise3.kr(0.1).linexp(-1, 1, density.linlin(0, 1, 0.9, 0.3) * clip.linlin(0, 1, 1, 0.01), clip.linlin(0, 1, 1, 0.001))
							).linlin(0, 1, 0.6 - clip.linexp(0, 1, 0.01, 0.6), 1),
							freq: 20 + (density.linexp(0, 1, 40, 6600) * clip.linlin(0, 1, 1, 0.01))
						);
					} {
						cut = \cut.kr(0.0).lag(5);

						sig = (WhiteNoise.ar(1) + sig) * hpEnv;
						// sig = sig + (sig * Lag3UD.ar(jumps[i] * pulseAmt * density.range(0.3, 10), 0.001, 0.7));
						// sig = sig * Lag3UD.ar(jumps[i], 0.001, 0.2);

						sig = HPF.ar(sig, 20000 - (density.range(9000, 20000) * hpEnv));
						sig = sig * LPF.ar(
							LFPulse.ar(
								[20, 30, 60].choose,
								(i % 2) * 0.5,
								LFNoise2.kr(0.1).exprange(density.range(0.9, 0.5), 1) * (1 - cut)
							).linlin(0, 1, cut, 1)
							, density.linlin(0, 1, 400, 1300)
						);

						sig = HPF.ar(sig, cut.linexp(0.25, 1, 10, 21000))
					};
					sig
				});

				volume = \volume.kr(0).lag(4).dbamp;
				sig = noise.scramble.clump(2).collect({
					| s, i |
					var leftSide, rightSide, pan;
					pan = i / (noise.size / 2);
					leftSide = PanArray.ar(2, s[0], pos: pan, width: 1);
					rightSide = PanArray.ar(2, s[1], pos: pan, width: 1);
					[leftSide, rightSide].flop.flatten;
					// structure: [[lf, lr], [rf, rr]] -> [[lf, rf], [lr, rr]] -> [lf, lr, rf, rr]
					//[s[0], s[1]];
				});
				sig = Mix(sig).assertChannels(4);
				sig = [sig[0] + sig[1], sig[2] + sig[3]]; // stereo

				pulseVol = \pulseVol.kr(-90).lag(1).dbamp;
				pulseSpeed = \pulseSpeed.kr(0).lag(1);
				if (lesser) {
					pulseImp = Impulse.ar([0.125, 0.25, 0.5, 1]);
					//pulseImp = Lag3UD.ar(pulseImp, 0.0001, [5, 4, 3, 2]);
					pulseImp = Env.perc(0.001, 1, curve:-4).ar(gate:pulseImp, timeScale: [10, 8, 6, 4]);
					pulseImp = SelectX.ar(pulseSpeed, pulseImp) * pulseVol;

					sig = sig + LPF.ar(LPF.ar(sig, 45), 45, pulseImp * -30) + LPF.ar(LPF.ar(sig, 400), 400, pulseImp * -4 );
					[RunningMax.ar(sig), RunningMin.ar(sig)].poll;
					sig
				} {
					pulseImp = Impulse.ar([0.125, 0.25, 0.5, 1]);
					// pulseImp = Lag3UD.ar(pulseImp, 0.0001, [5, 4, 3, 2]).pow(2);
					pulseImp = Env.perc(0.01, 1, curve:-4).ar(gate:pulseImp, timeScale: [10, 8, 6, 4]);
					pulseImp = SelectX.ar(pulseSpeed, pulseImp) * pulseVol;
					sig = (sig * 0.1) + LPF.ar(LPF.ar(sig, 45), 45, pulseImp * 800) + LPF.ar(LPF.ar(pulseImp * sig * -1, 640), 640, 3);
				};
				// sig = HPF.ar(Decay.ar( SelectX.ar(MouseY.kr(0, 3), Impulse.ar([0.5, 1, 2, 4])), 3) * sig, 18000, 0.05, 4);
				sig = LeakDC.ar(sig);



				sig = Compander.ar(sig, sig.sum / 8, 0.6, 1/6, 1/8, 1, 5);
				sig = -16.dbamp * sig * volume * EnvGen.kr(Env([0, 1, 1, 0], [10, 5, 20], releaseNode: 2),
					gate: \gate.kr(1),
					doneAction: 2
				);

				Out.ar(\out.ir(0), sig);
			},
			metadata:(
				specs: (
					volume:		ControlSpec(-40, 0,  			default: -40),
					density: 	ControlSpec(0, 1, 				default: 0),
					fx:			ControlSpec(0, ~chordSequenceLow.size - 0.5,
																default: 0),
					distAmt:	ControlSpec(0, 1, 				default: 0),
					clip:		ControlSpec(0, 1, warp:\sin,	default: 0),
					cut:		ControlSpec(0, 1, warp:\sin,	default: 0),
				)
			)
			).addReplace;
		};

		~massDef.(\lesser, true);
		~massDef.(\greater, false);

	~ctrl = ControlValueEnvir(BusControlValue);
	~ctrl.use {
		var lesser 			= 'mass.lesser'.asSynthDesc.metadata.specs;
		var greater 		= 'mass.greater'.asSynthDesc.metadata.specs;

		~lowVolume.spec		= lesser.volume;
		~lowDensity.spec	= lesser.density;
		~lowFx.spec 		= lesser.fx;
		~lowClip.spec		= lesser.clip;
		~lowDistAmt.spec	= lesser.distAmt;
		// ~lowDrop.spec		= lesser.drop.postln;

		~highVolume.spec 	= greater.volume;
		~highDensity.spec 	= greater.density;
		~highFx.spec		= greater.fx;
		~highCut.spec 		= greater.cut;
		~highDistAmt.spec	= greater.distAmt;
		// ~highDrop.spec 		= greater.drop.postln;

		~lowToggle			= OnOffControlValue(\off);
		~highToggle			= OnOffControlValue(\off);
	};

	~resources.addAll [
		~distBuffer = Buffer.alloc(s, 4092);
	];

	~distBuffer.plot;
	~distBuffer.zero();
	~distBuffer.cheby([3.0, 0, -1.1, 0], asWavetable:true);

	~t1 = Twister(\default);

});

////////////////////////////////////////////////////////////////////////////////
// STATES
////////////////////////////////////////////////////////////////////////////////

State(\mass).startActions.add({

	////////////////////////////////////////////////////////////////////////////////
	// LOW
	~t1.row(0)[0].knobCV 		= ~ctrl.lowVolume;
	~t1.row(0)[1].knobCV		= ~ctrl.lowDensity;
	~t1.row(0)[2].knobCV		= ~ctrl.lowDistAmt;

	~t1.row(1)[0].knobCV 		= ~ctrl.lowFx;
	~t1.row(1)[3].knobCV		= ~ctrl.lowClip;

	~t1.row(0)[0].buttonCV		= ~ctrl.lowToggle;
	~t1.row(0)[0].toggle 		= true;
	~t1.row(0)[0].ledColor_(Color.grey());

	////////////////////////////////////////////////////////////////////////////////
	// HIGH
	~t1.row(2)[0].knobCV 		= ~ctrl.highVolume;
	~t1.row(2)[1].knobCV		= ~ctrl.highDensity;
	~t1.row(2)[2].knobCV		= ~ctrl.highDistAmt;

	~t1.row(3)[0].knobCV 		= ~ctrl.highFx;
	~t1.row(3)[3].knobCV		= ~ctrl.highClip;

	~t1.row(2)[0].buttonCV		= ~ctrl.highToggle;
	~t1.row(2)[0].toggle 		= true;
	~t1.row(2)[0].ledColor_(Color.grey());

	////////////////////////////////////////////////////////////////////////////////
	// GRID
	CVGrid(\mass).rows_(4);
	CVGrid(\mass).fromEnvir(~ctrl.envir,
		*(~t1.knobs.collect(_.knobCV))
	);
	CVGrid(\mass).front;

	////////////////////////////////////////////////////////////////////////////////
	// TRIGGERS
	~connections.free;
	~connections = ConnectionList.makeWith {
		~ctrl.lowToggle.signal(\on).connectTo({
			Log(\mass, "low started");
			~t1.row(0)[0].ledColor_(Color.green());

			if (~lowSynth.notNil) { ~lowSynth.release() };

			~lowSynth = Synth('mass.lesser', [
				\volume: 	~ctrl.lowVolume.asMap,
				\density: 	~ctrl.lowDensity.asMap,
				\fx: 		~ctrl.lowFx.asMap,
				\clip: 		~ctrl.lowClip.asMap,
				\distAmt:	~ctrl.lowDistAmt.asMap,
				\distBuffer: ~distBuffer
			]);
		}.e);
		~ctrl.lowToggle.signal(\off).connectTo({
			Log(\mass, "low stopped");
			~t1.row(0)[0].ledColor_(Color.grey());

			~lowSynth.release;
			~lowSynth = nil;
		}.e);

		~ctrl.highToggle.signal(\on).connectTo({
			Log(\mass, "high started");
			~t1.row(2)[0].ledColor_(Color.green());

			if (~highSynth.notNil) { ~highSynth.release() };

			~highSynth = Synth('mass.greater', [
				\volume: 	~ctrl.highVolume.asMap,
				\density: 	~ctrl.highDensity.asMap,
				\fx: 		~ctrl.highFx.asMap,
				\cut: 		~ctrl.highCut.asMap,
				\distAmt:	~ctrl.highDistAmt.asMap,
				\distBuffer: ~distBuffer
			]);
		}.e);
		~ctrl.highToggle.signal(\off).connectTo({
			Log(\mass, "high stopped");
			~t1.row(2)[0].ledColor_(Color.grey());

			~highSynth.release;
			~highSynth = nil;
		}.e);
	};


	////////////////////////////////////////////////////////////////////////////////
	// LET
	// ~letTrigger = ~lc.buttons[7].default();
	// ~letTrigger.buttonOnActions.add(e{
	// 	Log(\mass, "let triggered");
	// 	Synth(\let, args:[\freq, 140]);
	// });

});

State(\mass).stopActions.add({
	~ctrl.highToggle.off;
	~ctrl.lowToggle.off;
});

