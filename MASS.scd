////////////////////////////////////////////////////////////////////////////////
// SYNTHDEFS

/*////////////////////////////////////////////////////////////////////////////////


State(\mass).doInit();
State(\mass).doStart();
State(\mass).doStop();


*/////////////////////////////////////////////////////////////////////////////////

LogWindow(\mass, [\LCDevice, \mass, \error]).front;
State(\mass).clear;
State(\mass).push;
State(\mass).autoEnvirWindow = true;

State(\mass).initActions.add({

	(
		~voiceCount = 40;
		~scale = Scale.dorian;
		~chordSequence = [
			[[1, 4, 6], 			{ 2.rand }],
			[[3, 5, 8], 			{ 2.rand }],
			[[0, 3, 7, 11], 		{ 2.rand }],
			[[1, 5, 10],  			{ 2.3.rand.floor }],
			[[-3, 1, 6, 13], 		{ 2.3.rand.floor }],
			[[-3, 4, 13], 			{ (0.3 + 2.8.rand).floor }],
			[[2, 4, 6, 13], 		{ 3.rand }],
			[[-1, 3, 8, 15], 		{ 3.rand }],
		];

		DistCurve(\mass1,
			[-1, 0, 1],
			[-1, 0, 1],
			//Env([-1, 0, 1], [0.5, 0.5], [20, -20])
		);



		~makeChordSequence = {
			| base |
			~chordSequence.collect {
				| chord, chordNum |
				Log(\mass).info("CHORD: %  (%)\t\t%", chordNum, chord[0], chord[1].def.sourceCode);

				~voiceCount.collect {
					| i |
					var degree = chord[0].wrapAt(i);
					var oct = chord[1].value;

					//Log(\mass).info("     deg: %\t\t oct: %", degree, oct);
					~scale.degreeToFreq(degree, base.midicps, oct)
				}
			}
		};

		~chordSequenceLow = ~makeChordSequence.(30);
		~chordSequenceHigh = ~makeChordSequence.(30 + 24);

		SynthDef(\lesser, {
			var pulse, pulse2, phase, noise, noise2, jumps, phases, density,
			pulseAmt, freqFade, sig, freqs, freqMult, fx, clip, filtSig, volume,
			bSig, a, b, c, d, e, f, g, h;

			density = \density.kr(0).lag(5);
			fx = \fx.kr(0).lag(5);
			clip = \clip.kr(5).lag(8);

			phase = LFNoise2.kr(0.1).range(0.06, 0.09);
			pulse = (Impulse.ar(3) * WhiteNoise.ar(2)) +
			(Impulse.ar(1, phase) * WhiteNoise.ar(2)) +
			(Impulse.ar(6, phase) * WhiteNoise.ar(1)) ;

			jumps = 2.collect({
				PanAz.ar(
					~voiceCount, pulse,
					pos: LFNoise2.kr(0.06).range(-1,1),
					width: LFNoise2.kr(0.07).range(2 + (density), 2 + (density * 4))
				)
			}).sum;
			jumps.assertChannels(~voiceCount);

			jumps = jumps * EnvGen.kr(Env([0, 0, 1, 1], [4, 4, 20]), timeScale:5);
			phases = jumps.collect({
				| jump |
				(2.0.rand + Integrator.ar(jump.abs.neg * 0.2, 1)) % (2 * pi);
			});

			pulseAmt = LFNoise2.kr(LFNoise2.kr(0.1).range(0.05, 0.2)).exprange(0.5, 1.0);

			freqs = phases.collect({
				| p, i |
				Select.kr(
					(fx.pow(Rand(1, 1)) * ~chordSequenceLow.size) + Rand(-0.25, 0.25), ~chordSequenceLow.flop[i]
				);
			});

			noise = phases.collect({
				| phase, i |
				var sig, degree, freq, freq1, freq2, saw, hpEnv, scale, bump;
				hpEnv = max(0, SinOsc.kr(1/100, phase.lag(0.1)).abs - density.linlin(0, 1, 0.55, 0.42)).lag(0.2);

				freq = freqs[i];

				if (i < 35) {
					freq = freq * (density.linlin(0, 1, 1.0, 1 + Rand(-0.02, 0.02)) + [0.03.rand, 0.02.rand, 0.04.rand]);
					saw = LFSaw.ar(freq).sum * density.range(0.4, 1.0);
				} {
					freq = freq * (density.linlin(0, 1, 1.0, Rand(-0.03, 0.03)) + [0.015.rand, 0.01.rand, 0.021.rand]);
					saw = LFPulse.ar(freq, 0, density.range(0, 0.99)).sum * max(density - 0.5, 0) * 1;
				};

				sig = saw;
				sig = (sig + (BrownNoise.ar(0.5 + density.linlin(0, 1, 0, 0.5)) * sig)) * hpEnv;

//				sig = DistCurve(\mass1).ar(sig, 1, );

				sig = LPF.ar(sig, max(density.linexp(0, 1, 10, 14000) * hpEnv, 20), 1);

				filtSig = HPF.ar(sig, clip.range(500, 18000), mul: clip.range(1, 4.0)) +
				LPF.ar(sig, clip.range(20000, 40), mul:0);

				sig = XFade2.ar(sig, filtSig, clip.range(-1, 1));

				sig * LPF.ar(
					in: LFPulse.ar(
						freq: 	[20, 30, 60].choose,
						iphase:	i % 2 * 0.5,
						width:	LFNoise2.kr(0.1).linexp(-1, 1, density.linlin(0, 1, 0.9, 0.3) * clip.linlin(0, 1, 1, 0.01), clip.linlin(0, 1, 1, 0.001)).poll
					).linlin(0, 1, 0.6 - clip.linexp(0, 1, 0.01, 0.6), 1),
					freq: 20 + (density.linexp(0, 1, 40, 1600) * clip.linlin(0, 1, 1, 0.01))
				);
			});

			volume = \volume.kr(0).lag(4);
			sig = noise.clump(2).collect({
				| s, i |
				var leftSide, rightSide, pan;
				pan = i / (noise.size / 2);
				leftSide = PanArray.ar(4, s[0], pos: pan, width: density.linlin(0, 1, 2, 3));
				rightSide = PanArray.ar(4, s[1], pos: pan, width: density.linlin(0, 1, 2, 3));
				[leftSide, rightSide].flop.flatten;

				[s[0], s[1]];
			});

			sig = Mix(sig).assertChannels(2);
			sig = Compander.ar(sig, sig.sum / 8, 0.6, 1/6, 1/8, 1, 5);
			sig = -16.dbamp * sig * volume * EnvGen.kr(Env([0, 1, 1, 0], [10, 5, 20], releaseNode: 2),
				gate: \gate.kr(1),
				doneAction: 2
			);

			Out.ar(\out.ir(0), sig);
		}).addReplace;

		SynthDef(\greater, {
			var pulse, pulse2, phase, noise, noise2, jumps, phases, pulseAmt, freqFade, density, sig, freqs, fx, volume,
			a, b, c, d, e, f, g, h, bSig, cut;

			density = \density.kr(0).lag(5);
			fx = \fx.kr(0).lag(5);

			phase = LFNoise2.kr(0.1).range(0.06, 0.09);
			pulse = ((Impulse.ar(3) * WhiteNoise.ar(2)) +
				(Impulse.ar(1, phase) * WhiteNoise.ar(2)) +
				(Impulse.ar(6, phase) * WhiteNoise.ar(1))
			);

			jumps = 2.collect({
				PanAz.ar(
					~voiceCount, pulse,
					pos: LFNoise2.kr(0.06).range(-1, 1),
					width: LFNoise2.kr(0.07).range(2 + (density * 10), 2 + (density * 20))
				)
			}).sum;

			jumps = jumps * EnvGen.kr(Env([0, 0, 1, 1], [4, 4, 20]), timeScale:5);
			phases = jumps.collect({
				| jump |
				(2.0.rand + Integrator.ar(jump.abs.neg * 0.2, 1)) % (2 * pi);
			});

			pulseAmt = LFNoise2.kr(LFNoise2.kr(0.2).range(0.1, 0.3)).exprange(0.5, 2.0);

			freqs = phases.collect({
				| p, i |
				Select.kr(
					(fx.pow(Rand(1, 5)) * 6) + Rand(-0.25, 0.25), ~chordSequenceHigh[i]
				);
			});

			noise = phases.collect({
				| phase, i |
				var sig, degree, freq, freq1, freq2, saw, hpEnv, scale;
				hpEnv = max(0, SinOsc.kr(0.007, phase.lag(0.2)).abs - density.exprange(0.9, 0.22));
				freq = freqs[i];

				if (i < 35) {
					freq = freq * (density.range(1.0, 1.01) + [0.03.rand, 0.02.rand, 0.04.rand]);
					saw = LFSaw.ar(freq).sum * density.range(0.2, 1.0);
				} {
					freq = freq * (density.range(1, 1) + [0.03.rand, 0.01.rand, 0.02.rand]);
					saw = LFSaw.ar(freq).sum * max(density - 0.5, 0);
				};

				sig = saw;
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
			});

			volume = \volume.kr(0).lag(4);
			sig = noise.clump(2).collect({
				| s, i |
				var a, b, c, d, e, f, g, h, n, pan;
				pan = (i / (noise.size / 2)) * 2 - 1;
				#a, c, n, e, g = PanAz.ar(5, s[0], pos: pan, width: density.linlin(0, 1, 2, 3), );
				#b, d, n, f, h = PanAz.ar(5, s[1], pos: pan, width: density.linlin(0, 1, 2, 3), );
				[a, b, c, d, e, f, g, h];

				[s[0], s[1]];
			});
			sig = Mix(sig);
			sig = Compander.ar(sig, sig.sum / 8, 0.6, 1/6, 1/8, 1, 5);
			sig = -16.dbamp * sig * volume * EnvGen.kr(Env([0, 1, 1, 0], [10, 5, 20], releaseNode: 2),
				gate: \gate.kr(1),
				doneAction: 2
			);
			// bSig = Mix(noise.collect({ |n, i| PanB2.ar(n, (i / noise.size).linlin(0, 1, -1, 1)) }));
			//
			// bSig = Compander.ar(bSig, bSig.sum / 4, 0.6, 1/6, 1/8, 1, 5);
			// bSig = -12.dbamp * bSig * volume * EnvGen.kr(Env([0, 1, 1, 0], [10, 5, 20], releaseNode: 2),
			// 	gate: \gate.kr(1),
			// 	doneAction: 2
			// );
			//
			// #a, c, d, b = DecodeB2.ar(4, bSig[0], bSig[1], bSig[1], 0.5);
			// #e, g, h, f = DecodeB2.ar(4, bSig[0], bSig[1], bSig[1], 0.5);
			//
			//Out.ar(\out.ir(0), [a, b, c, d, e, f, g, h]);
			//#a, b = B2UHJ.ar(*bSig);
			//Out.ar(\out.ir(0), [a, b]);
			Out.ar(\out.ir(0), sig);
		}).addReplace;
	);

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

	Event.parentEvents[\cvSynth] = CVEvent.synthEvent;

	~lc.notNil.if({ ~lc.free });
	~lc = LCDevice();
	~lc.connect();
	~lc.knobs.do(_.ringStyle_(\fill));

	// Play button
	~playButton = ~lc.buttons[4].default;
	~playButton.toggle = true;
	~playButton.buttonOnActions.add({
		State(\mass).doStart();
	});

	~playButton.buttonOffActions.add({
		State(\mass).doStop();
	});

	~lastLow = inf;
	~lastHigh = inf;

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
// STATES
////////////////////////////////////////////////////////////////////////////////

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
	// let
	~letTrigger = ~lc.buttons[7].default();
	~letTrigger.buttonOnActions.add(e{
		Log(\mass, "let triggered");
		Synth(\let);
	});

});

State(\mass).stopActions.add({
	~highTrigger.cv.value = 0;
	~lowTrigger.cv.value = 0;
	~knobs.do(_.cv_(nil));
});

