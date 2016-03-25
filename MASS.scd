
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
	);

	~controls = [
		~lowVolume = CV(ControlSpec(0, 1, warp: 6, default: 0.0)),
		~lowDensity = CV(ControlSpec(0, 1, default: 0.0)),
		~lowFx = CV(ControlSpec(0, 1, default: 0.0)),
		~lowClip = CV(ControlSpec(0.0, 1.0, warp:\sin, default: 0.0)),
		~lowDrop = CV(ControlSpec(0, 1, step: 1, default: 0)),

		~highVolume = CV(ControlSpec(0, 1, warp: 6, default: 0.0)),
		~highDensity = CV(ControlSpec(0, 1, default: 0.0)),
		~highFx = CV(ControlSpec(0, 1, default: 0.0)),
		~highCut = CV(ControlSpec(0, 1, warp:\sin, default: 0.0)),
		~highDrop = CV(ControlSpec(0, 1, step: 1, default: 0)),
	];
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
					hpEnv = max(0, SinOsc.kr(1 / 100, phase.lag(0.1)).abs - density.linlin(0, 1, 0.55, 0.42)).lag(0.2);
					// hpEnv = max(0, SinOsc.kr(0.007, phase.lag(0.2)).abs - density.exprange(0.9, 0.22)); // greater
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
						sig = sig + (jumps[i] * pulseAmt * density.range(0.3, 2));
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
					leftSide = PanArray.ar(4, s[0], pos: pan, width: density.linlin(0, 1, 2, 3));
					rightSide = PanArray.ar(4, s[1], pos: pan, width: density.linlin(0, 1, 2, 3));
					[leftSide, rightSide].flop.flatten;

					[s[0], s[1]];
				});
				// sig = sig + RLPF.ar(Decay.ar( SelectX.ar(MouseY.kr(0, 3), Impulse.ar([0.5, 1, 2, 4])), 3) * sig, 50, 0.05, 4);
				sig = LeakDC.ar(sig);

				sig = Mix(sig).assertChannels(2);
				sig = sig + SoftClipAmp8.ar([
					LeakDC.ar(SelectXFocus.ar(MouseX.kr(0, noise.size - 1), noise.scramble, 0.25)),
					LeakDC.ar(SelectXFocus.ar(MouseX.kr(0, noise.size - 1), noise.scramble, 0.25))
				], 2, density.linlin(0, 1, 0, 2));

				Out.ar(100, noise);

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


	~resources.addAll [
		~distBuffer = Buffer.alloc(s, 4092);
	];

	~distBuffer.cheby([3.1, 1.5, 1.5, -1, 1, 0, 1], asWavetable:true);
	~distBuffer.cheby([3.1, 0, 1.6], asWavetable:true);


	DistCurve(\mass1,
		[-1, 0, 1],
		[-1, 0, 1],
		//Env([-1, 0, 1], [0.5, 0.5], [20, -20])
	);

});

State(\mass).startActions.add {

};
////////////////////////////////////////////////////////////////////////////////
// STATES
////////////////////////////////////////////////////////////////////////////////

SynthDef(\let, {
	var env, sig;
	env = EnvGen.kr(Env.perc(0.01, 20, curve: -16), doneAction:2);
	sig = RLPF.ar(LFSaw.ar(env.range(30, 44) + Rand(0, [2.0, 3.0])), 40,  0.01) * env * 0.1;
	//sig = sig.fold2(0.6);
	sig = sig.tanh;
	sig = RLPF.ar(sig, 260);
	sig = HPF.ar(sig, 17);
	sig = sig.tanh * 1.4;
	Out.ar(\out.ir([0, 1]), sig);
}).add;



~lowFx.action_(e({
	|cv|
	var val = (cv.value * ~chordSequenceLow.size * 0.99999).floor.asInteger;
	if (~lastLow != val) {
		~lastLow = val;
		Log(\mass).info("LOW SEQUENCE %%", val.asString().padLeft(val + 1));
		Log(\mass).info(~chordSequence[val].asString())
	}
}))

});
	////////////////////////////////////////////////////////////////////////////////
	// LOW


State(\mass).startActions.add({
	~knobs = List();

	////////////////////////////////////////////////////////////////////////////////
	// low
	~controls[0..4].do({
		|cv, i|
		~knobs.add(
			~lc.knobs[3 + (i * 4)].cv_(cv)
		);
	});

	// FX controls
	~lc.knobRows[2][2].step = 1/400;
	~lc.knobRows[3][2].step = 1/400;

	~lowTrigger = ~lc.buttons[6].default();
	~lowTrigger.toggle = true;
	~lowTrigger.buttonOnActions.add(e{
		Log(\mass, "low started");
		if (~lowSynth.notNil) { ~lowSynth.release() };

		~lowSynth = Synth.controls(\lesser, [
			\volume: 		~lowVolume,
			\density: 		~lowDensity,
			\fx: 			~lowFx,
			\clip: 			~lowClip,
			\drop:			~lowDrop,
		]);
	});
	~lowTrigger.buttonOffActions.add(e{
		Log(\mass, "low stopped");
		~lowSynth.release;
		~lowSynth = nil;
	});


	////////////////////////////////////////////////////////////////////////////////
	// high
	~controls[5..8].do({
		|cv, i|
		~knobs.add(
			~lc.knobs[2 + (i * 4)].cv_(cv)
		);
	});
	~highTrigger = ~lc.buttons[5].default();
	~highTrigger.toggle_(true);
	~highTrigger.buttonOnActions.add(e{
		Log(\mass, "high started");
		if (~highSynth.notNil) { ~highSynth.release() };

		~highSynth = Synth.controls(\greater, [
			\volume: 		~highVolume,
			\density: 		~highDensity,
			\fx: 			~highFx,
			\cut: 			~highCut
		]);
	});
	~highTrigger.buttonOffActions.add(e{
		Log(\mass, "high stopped");
		~highSynth.release;
		~highSynth = nil;
	});

	////////////////////////////////////////////////////////////////////////////////
	// LET
	// ~letTrigger = ~lc.buttons[7].default();
	// ~letTrigger.buttonOnActions.add(e{
	// 	Log(\mass, "let triggered");
	// 	Synth(\let, args:[\freq, 140]);
	// });

});

State(\mass).stopActions.add({
	~highTrigger.cv.value = 0;
	~lowTrigger.cv.value = 0;
	~knobs.do(_.cv_(nil));
});

