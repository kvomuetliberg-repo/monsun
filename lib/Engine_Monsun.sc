// Engine_Monsun
// A 16-tap rhythm delay and a 64-tooth comb resonator, after the Intellijel / Cylonix Rainmaker.
//
// Synths, in this order (the comb group runs before the delay group when the comb feeds the delay):
//   src          line in / file / demo, input gain, ping                         -> srcBus
//   delay group  core: write pointer, freeze and reverse, feedback (one tap or all taps,
//                with its own pitch shifter and tone filter) into one mono 32 s buffer
//                4 tap synths, 4 taps each: two-grain pitch shifter, LP/BP/HP filter, level, pan -> dBus
//   comb group   core: input, pluck exciter, the feedback loop (guitar, sitar, clarinet, raw)
//                written into the comb buffer; tooth 64 is the comb size and sets the pitch
//                4 teeth synths, 16 teeth each                                   -> cBus
//   mix          routing, delay <> comb balance, dry/wet, output level, limiter, polls
//
// Splitting the taps and teeth across synths keeps each synth within norns' default of
// 64 wire buffers. The feedback loops run through their buffers, which keeps them
// sample-accurate for loops of at least one 64-sample block; shorter comb sizes (notes
// above about F5) use SuperCollider's sample-accurate comb filters.
//
// Polls: in_db, dly_db, cmb_db, out_db.

Engine_Monsun : CroneEngine {
	var <srcSyn, <delCore, <delTaps, <combCore, <combTeeth, <mixSyn, <dGroup, <cGroup;
	var <dbuf, <cbuf, <fbbuf, <bufFile, <bufDemo;
	var <srcBus, <dBus, <cBus, <refBus, <lfoBus, <sumBus, <cwBus, <sizeBus, <pollBus;
	var routing = 0, toothGains;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		var s = context.server;
		dbuf = Buffer.alloc(s, s.sampleRate.asInteger * 32, 1);
		cbuf = Buffer.alloc(s, (s.sampleRate * 2.5).asInteger, 1);
		fbbuf = Buffer.alloc(s, (s.sampleRate * 1.5).asInteger, 1);
		bufFile = Buffer.alloc(s, 64, 2);
		bufDemo = Buffer.alloc(s, 64, 2);
		srcBus = Bus.audio(s, 2); dBus = Bus.audio(s, 2); cBus = Bus.audio(s, 2);
		refBus = Bus.audio(s, 1); lfoBus = Bus.audio(s, 1); sumBus = Bus.audio(s, 1); cwBus = Bus.audio(s, 1);
		sizeBus = Bus.control(s, 1); pollBus = Bus.control(s, 4);
		toothGains = 0 ! 64;

		// --- BEGIN SYNTHDEFS ---
		SynthDef(\monsunSrc, {
			var source = \source.kr(0);
			var line = [In.ar(\inL.kr(0)), In.ar(\inR.kr(0))];
			var file = PlayBuf.ar(2, \bufFile.kr(0), BufRateScale.kr(\bufFile.kr(0)), loop: 1);
			var demo = PlayBuf.ar(2, \bufDemo.kr(0), BufRateScale.kr(\bufDemo.kr(0)), loop: 1);
			var x = Select.ar(source, [line, file, demo]) * Lag.kr(\inGain.kr(0), 0.05).dbamp;
			var trig = \t_ping.tr(0);
			var ping = WhiteNoise.ar * EnvGen.ar(Env([0, 1, 0], [0, 0.015], -6), trig) * Latch.kr(\pingAmp.kr(1), trig);
			Out.ar(\out.kr(0), x + ping);
		}).add;

		// delay core: pointer, feedback, write
		SynthDef(\monsunDelayCore, {
			var sr = SampleRate.ir;
			var dbuf = \dbuf.kr(0), frames = BufFrames.kr(\dbuf.kr(0));
			var fbbuf = \fbbuf.kr(0), fbFrames = BufFrames.kr(\fbbuf.kr(0));
			var src = In.ar(\srcBus.kr(0), 2), m = src.sum * 0.5;
			var cm = In.ar(\cBus.kr(0), 2).sum * 0.5;
			var routing = \routing.kr(0), bal = Lag.kr(\balance.kr(0), 0.05);
			var x = Select.ar(routing, [m, (m * (1 - bal)) + (cm * bal), m, src[0]]);
			var fz = \freeze.kr(0), rv = \reverse.kr(0);
			var gs = (\grain.kr(0.084) * sr).max(32);
			var fbT = Lag.kr(\fbTime.kr(2).max(0.0016), 0.4);
			var fbAll = \fbAll.kr(0), fbRatio = \fbRatio.kr(1);
			var fbTone = Lag.kr(\fbTone.kr(0), 0.05), fbAmt = Lag.kr(\fb.kr(0.35), 0.05);
			var tw = \tlfoWave.kr(0), tr = \tlfoRate.kr(0.5), td = Lag.kr(\tlfoDepth.kr(0.002), 0.1);
			var lfo, lfoS, wp, loopLen, loopTrig, loopPh, wrapped, frzEnd, revAnchor, mode, ref;
			var fbx, fwp, fbw, fbp, fbs, lpc, hpc, fbo, wIn;

			lfo = Select.kr(tw, [DC.kr(0), SinOsc.kr(tr), LFTri.kr(tr),
				(SinOsc.kr(tr) * 0.8) + (SinOsc.kr(tr * 3) * 0.2),
				SinOsc.kr(tr) * (0.5 + (0.5 * SinOsc.kr(tr * 0.5))),
				LFSaw.kr(tr).neg, LFSaw.kr(tr), LFNoise2.kr(tr)]);
			lfoS = K2A.ar(lfo * td * sr);

			// "now" pointer: normal, frozen loop, reverse
			wp = Phasor.ar(0, 1 - fz, 0, frames);
			loopLen = (fbT * sr).clip(64, 6 * sr);
			loopTrig = T2A.ar((HPZ1.kr(fz).abs > 0) + (HPZ1.kr(rv) > 0));
			loopPh = Phasor.ar(loopTrig, 1, 0, loopLen);
			wrapped = loopPh < Delay1.ar(loopPh);
			frzEnd = Latch.ar(wp, T2A.ar(HPZ1.kr(fz) > 0));
			revAnchor = Latch.ar(wp, loopTrig + wrapped);
			mode = (fz * (1 + rv)) + ((1 - fz) * rv * 3);
			ref = Select.ar(mode, [wp, frzEnd - loopLen + loopPh, frzEnd - loopPh, revAnchor - loopPh]);

			// feedback: one tap (pre-filter, from the buffer) or all taps (post-filter, one block later)
			fbx = BufRd.ar(1, dbuf, (ref - (fbT * sr) - lfoS - 1).min(ref - 3).wrap(0, frames), 1, 4);
			fbx = Select.ar(fbAll, [fbx, InFeedback.ar(\sumBus.kr(0))]);
			fwp = Phasor.ar(0, 1, 0, fbFrames);
			fbw = BufWr.ar(fbx, fbbuf, fwp);
			fbp = Phasor.ar(0, (1 - fbRatio) / gs, 0, 1);
			fbs = [fbp, (fbp + 0.5).wrap(0, 1)].collect { |f|
				BufRd.ar(1, fbbuf, (fwp - (f * gs) - 1 + fbw.abs.min(0)).wrap(0, fbFrames), 1, 2) * (f * pi).sin.squared
			}.sum;
			fbx = Select.ar((fbRatio - 1).abs < 0.0001, [fbs, fbx]);
			lpc = exp(-2pi * (20000 * ((300 / 20000) ** fbTone.neg.max(0))) / sr);
			hpc = exp(-2pi * (20 * (150 ** fbTone.max(0))) / sr);
			fbx = Select.ar((fbTone < -0.01) + ((fbTone > 0.01) * 2), [fbx, OnePole.ar(fbx, lpc), fbx - OnePole.ar(fbx, hpc)]);
			fbo = (LeakDC.ar(fbx, 0.9995) * fbAmt * 1.05).tanh;

			// write; while frozen the buffer keeps its content
			wIn = Select.ar(fz, [x + fbo, BufRd.ar(1, dbuf, wp, 1, 1)]);
			BufWr.ar(wIn, dbuf, wp);
			Out.ar(\refBus.kr(0), ref);
			Out.ar(\lfoBus.kr(0), lfoS);
			// delay bypassed: its input passes straight through
			Out.ar(\dBus.kr(0), [x, x] * (1 - \delayOn.kr(1)));
		}).add;

		// four taps; runs after the core, so the buffer already holds this block
		SynthDef(\monsunTaps, {
			var sr = SampleRate.ir;
			var dbuf = \dbuf.kr(0), frames = BufFrames.kr(\dbuf.kr(0));
			var ref = In.ar(\refBus.kr(0)), lfoS = In.ar(\lfoBus.kr(0));
			var gs = (\grain.kr(0.084) * sr).max(32);
			var tapT = Lag.kr(\tapT.kr([1, 2, 3, 4] * 0.125), 0.4);
			var tapLvl = Lag.kr(\tapLvl.kr(0.5 ! 4), 0.05);
			var tapPan = Lag.kr(\tapPan.kr(0 ! 4), 0.05);
			var tapType = \tapType.kr(0 ! 4);
			var tapCut = Lag.kr(\tapCut.kr(3000 ! 4), 0.05);
			var tapQ = Lag.kr(\tapQ.kr(0.3 ! 4), 0.05);
			var tapRatio = \tapRatio.kr(1 ! 4);
			var sum = 0, outL = 0, outR = 0, on = \delayOn.kr(1);
			var refL = ref - lfoS - 1, guard = ref - 3;
			4.do { |i|
				// 3 ms earlier: the output limiter's look-ahead delays the wet signal by that much
				var pos = (refL - ((tapT[i] - 0.003).max(0.0005) * sr)).min(guard);
				var r = tapRatio[i];
				// two crossfading grains; unpitched, both read the same position, which gives the plain tap
				var g = gs * ((r - 1).abs > 0.0001);
				var ph = Phasor.ar(0, (1 - r) / gs, 0, 1), f2 = ph + 0.5 - (ph >= 0.5);
				var w1 = 1 - ((ph * 2) - 1).abs;
				var s = (BufRd.ar(1, dbuf, pos - (ph * g), 1, 2) * w1) + (BufRd.ar(1, dbuf, pos - (f2 * g), 1, 2) * (1 - w1));
				// one biquad per tap: low, band or high pass coefficients chosen at control rate
				var k = (2 - (1.97 * tapQ[i])).max(0.03), w = 2pi * tapCut[i].clip(20, sr * 0.45) / sr;
				var cw = w.cos, al = w.sin * k * 0.5, a0 = 1 + al, t = tapType[i];
				var ff0 = Select.kr(t, [1, (1 - cw) * 0.5 / a0, al / a0, (1 + cw) * 0.5 / a0]);
				var ff1 = Select.kr(t, [0, (1 - cw) / a0, 0, (1 + cw).neg / a0]);
				var ff2 = Select.kr(t, [0, (1 - cw) * 0.5 / a0, al.neg / a0, (1 + cw) * 0.5 / a0]);
				var fb1 = Select.kr(t, [0, 2 * cw / a0, 2 * cw / a0, 2 * cw / a0]);
				var fb2 = Select.kr(t, [0, (1 - al).neg / a0, (1 - al).neg / a0, (1 - al).neg / a0]);
				var f = SOS.ar(s, ff0, ff1, ff2, fb1, fb2);
				f = Select.ar(t > 0, [f, f.tanh]) * tapLvl[i];
				sum = sum + f;
				outL = outL + (f * ((tapPan[i] + 1) * 0.25pi).cos);
				outR = outR + (f * ((tapPan[i] + 1) * 0.25pi).sin);
			};
			Out.ar(\sumBus.kr(0), sum * 0.5);
			Out.ar(\dBus.kr(0), [outL, outR] * 0.45 * on);
		}).add;

		// comb core: input, exciter, feedback loop, write
		SynthDef(\monsunCombCore, {
			var sr = SampleRate.ir;
			var cbuf = \cbuf.kr(0), frames = BufFrames.kr(\cbuf.kr(0));
			var src = In.ar(\srcBus.kr(0), 2), m = src.sum * 0.5, d = In.ar(\dBus.kr(0), 2);
			var routing = \routing.kr(0);
			var trig = \t_pluck.tr(0), size = \size.kr(0.01);
			var len = Latch.kr(size.clip(0.002, 0.03), trig);
			var exc = Select.ar(\exciter.kr(0), [
				WhiteNoise.ar(0.9) * EnvGen.ar(Env([0, 1, 1, 0], [0, 1, 0]), trig, timeScale: len),
				EnvGen.ar(Env.sine(1), trig, timeScale: len) * 1.2
			]) * Latch.kr(\pluckAmp.kr(1), trig);
			var xin = Select.ar(routing, [d.sum * 0.5, m, m, src[1]]);
			var sw = \slfoWave.kr(0), srate = \slfoRate.kr(0.3);
			var slfo = Select.kr(sw, [DC.kr(0), SinOsc.kr(srate), LFTri.kr(srate),
				(SinOsc.kr(srate) * 0.8) + (SinOsc.kr(srate * 3) * 0.2),
				SinOsc.kr(srate) * (0.5 + (0.5 * SinOsc.kr(srate * 0.5))),
				LFSaw.kr(srate).neg, LFSaw.kr(srate), LFNoise2.kr(srate)]);
			var sizeS = Lag.kr(size, \glide.kr(0).max(0.005));
			var sz = (sizeS * (1 + (slfo * \slfoDepth.kr(0.01)))).clip(2 / sr, 2.3);
			var szs = sz * sr;
			var g = (\combFb.kr(0.94) ** (sz.min(0.02) / 0.02)).min(0.9995);
			// gain staging: the stronger the resonance, the less of the input goes in (plucks are not scaled)
			var x = (xin * (2 * (1 - g).sqrt).min(1)) + exc;
			var type = \combType.kr(0);
			var isSitar = (type - 1).abs < 0.5;
			var cw = Phasor.ar(0, 1, 0, frames);
			var env = OnePole.ar(x.abs, 0.99);
			var szl = szs - Select.kr(type > 2.5, [0.5, 0]);
			var r = BufRd.ar(1, cbuf, (cw - (szl * (1 + (K2A.ar(isSitar) * 0.015 * (env * 4).min(1))))).wrap(0, frames), 1, 2);
			var avg = (r + Delay1.ar(r)) * 0.5;
			var y = Select.ar(type, [avg, avg, (avg * 1.6).tanh / 1.6, Select.ar(r.abs > 1, [r, r.tanh])]);   // clarinet: saturates loud notes, unity gain for quiet ones
			var loopFb = LeakDC.ar(y * g, 0.9995);
			// very short sizes (notes above about F5): sample-accurate comb filters
			var dec = (-3 * sz / g.max(0.0001).log10).clip(0.0005, 60);
			var yShort = Select.ar(type, [
				OnePole.ar(CombC.ar(x, 0.0016, sz, dec * 0.8), 0.25),
				OnePole.ar(CombC.ar(x, 0.0016, sz, dec * 0.8), 0.25),
				(CombC.ar(x, 0.0016, sz * 0.5, dec.neg) * 1.6).tanh / 1.6,
				CombC.ar(x, 0.0016, sz, dec)
			]);
			var w = x + Select.ar(szs < 66, [loopFb, yShort * g]);
			BufWr.ar(w, cbuf, cw);
			Out.ar(\cwBus.kr(0), cw);
			Out.kr(\sizeBus.kr(0), szs);
			// comb bypassed: its input passes straight through
			Out.ar(\cBus.kr(0), [x, x] * (1 - \combOn.kr(1)));
		}).add;

		// sixteen teeth; tooth 64 (the comb size) sits in the centre, the others alternate
		SynthDef(\monsunTeeth, {
			var cbuf = \cbuf.kr(0), frames = BufFrames.kr(\cbuf.kr(0));
			var cw = In.ar(\cwBus.kr(0)), szs = In.kr(\sizeBus.kr(0));
			var first = \first.ir(0);
			var tooth = \tooth.kr((1..16) / 64), toothG = \toothG.kr(0 ! 16);
			var oL = 0, oR = 0, on = \combOn.kr(1);
			16.do { |i|
				var t = BufRd.ar(1, cbuf, cw - (tooth[i] * szs), 1, 2) * toothG[i];
				var k = first + i;
				var centre = k > 62.5, right = ((63 - k) % 2) > 0.5;
				oL = oL + (t * Select.kr(centre, [1 - right, 0.5.sqrt]));
				oR = oR + (t * Select.kr(centre, [right, 0.5.sqrt]));
			};
			Out.ar(\cBus.kr(0), [oL, oR] * 2 * on);
		}).add;

		SynthDef(\monsunMix, {
			var src = In.ar(\srcBus.kr(0), 2), d = In.ar(\dBus.kr(0), 2), c = In.ar(\cBus.kr(0), 2);
			var routing = \routing.kr(0), bal = Lag.kr(\balance.kr(0), 0.05), mix = Lag.kr(\mix.kr(0.5), 0.05);
			var par = (d * (1 - bal)) + (c * bal);
			var wl = Select.ar(routing, [par[0], d[0], par[0], (d[0] + d[1]) * 0.7]);
			var wr = Select.ar(routing, [par[1], d[1], par[1], (c[0] + c[1]) * 0.7]);
			var dg = (mix * 0.5pi).cos, wg = (mix * 0.5pi).sin;
			var lvl = Lag.kr(\outLevel.kr(0), 0.05).dbamp;
			// only the wet signal goes through the limiter (it adds a few ms of look-ahead); the dry signal stays undelayed
			var wet = Limiter.ar(LeakDC.ar([wl, wr] * wg * lvl, 0.9995), 0.9, 0.0015);
			var o = ((src * dg * lvl) + wet).clip2(1);
			Out.kr(\pollBus.kr(0), [
				Amplitude.kr(src.sum * 0.5, 0.001, 0.25), Amplitude.kr(d.sum, 0.001, 0.25),
				Amplitude.kr(c.sum, 0.001, 0.25), Amplitude.kr(o[0], 0.001, 0.25)
			].collect { |a| (a + 1e-5).ampdb.max(-90) });
			Out.ar(\out.kr(0), o);
		}).add;
		// --- END SYNTHDEFS ---

		s.sync;

		srcSyn = Synth.new(\monsunSrc, [\inL, context.in_b[0].index, \inR, context.in_b[1].index,
			\bufFile, bufFile, \bufDemo, bufDemo, \out, srcBus.index], context.xg, \addToTail);
		dGroup = Group.new(context.xg, \addToTail);
		cGroup = Group.new(context.xg, \addToTail);
		delCore = Synth.new(\monsunDelayCore, [\dbuf, dbuf, \fbbuf, fbbuf, \srcBus, srcBus.index, \cBus, cBus.index,
			\dBus, dBus.index, \refBus, refBus.index, \lfoBus, lfoBus.index, \sumBus, sumBus.index], dGroup, \addToTail);
		delTaps = 4.collect { |j|
			Synth.new(\monsunTaps, [\dbuf, dbuf, \refBus, refBus.index, \lfoBus, lfoBus.index, \sumBus, sumBus.index,
				\dBus, dBus.index, \tapT, ((j * 4) + [1, 2, 3, 4]) * 0.125], dGroup, \addToTail)
		};
		combCore = Synth.new(\monsunCombCore, [\cbuf, cbuf, \srcBus, srcBus.index, \dBus, dBus.index,
			\cBus, cBus.index, \cwBus, cwBus.index, \sizeBus, sizeBus.index], cGroup, \addToTail);
		combTeeth = 4.collect { |j|
			Synth.new(\monsunTeeth, [\cbuf, cbuf, \cwBus, cwBus.index, \sizeBus, sizeBus.index, \cBus, cBus.index,
				\first, j * 16, \tooth, ((j * 16) + (1..16)) / 64], cGroup, \addToTail)
		};
		mixSyn = Synth.new(\monsunMix, [\srcBus, srcBus.index, \dBus, dBus.index, \cBus, cBus.index,
			\pollBus, pollBus.index, \out, context.out_b.index], context.xg, \addToTail);

		// --- commands (tap and tooth indices are 1-based, as in Lua) ---
		[[\tap_time, \tapT, { |v| v.clip(0.0005, 19.5) }], [\tap_level, \tapLvl, { |v| v }],
		 [\tap_pan, \tapPan, { |v| v.clip(-1, 1) }], [\tap_cut, \tapCut, { |v| v }],
		 [\tap_q, \tapQ, { |v| v.clip(0, 1) }], [\tap_pitch, \tapRatio, { |v| 2 ** (v / 12) }]].do { |c|
			this.addCommand(c[0], "if", { arg msg; this.setTap(msg[1], c[1], c[2].(msg[2])) });
		};
		this.addCommand("tap_ftype", "ii", { arg msg; this.setTap(msg[1], \tapType, msg[2]) });
		this.addCommand("grain", "f", { arg msg; dGroup.set(\grain, msg[1]) });
		this.addCommand("fb", "f", { arg msg; delCore.set(\fb, msg[1]) });
		this.addCommand("fb_time", "f", { arg msg; delCore.set(\fbTime, msg[1].clip(0.0016, 19.5)) });
		this.addCommand("fb_all", "i", { arg msg; delCore.set(\fbAll, msg[1]) });
		this.addCommand("fb_pitch", "f", { arg msg; delCore.set(\fbRatio, 2 ** (msg[1] / 12)) });
		this.addCommand("fb_tone", "f", { arg msg; delCore.set(\fbTone, msg[1]) });
		this.addCommand("tlfo_wave", "i", { arg msg; delCore.set(\tlfoWave, msg[1]) });
		this.addCommand("tlfo_depth", "f", { arg msg; delCore.set(\tlfoDepth, msg[1]) });
		this.addCommand("tlfo_rate", "f", { arg msg; delCore.set(\tlfoRate, msg[1]) });
		this.addCommand("freeze", "i", { arg msg; delCore.set(\freeze, msg[1]) });
		this.addCommand("reverse", "i", { arg msg; delCore.set(\reverse, msg[1]) });
		this.addCommand("clear", "", { [dbuf, cbuf, fbbuf].do(_.zero) });
		this.addCommand("delay_on", "i", { arg msg; dGroup.set(\delayOn, msg[1]) });

		this.addCommand("comb_size", "f", { arg msg; combCore.set(\size, msg[1].clip(0.0002, 2.1)) });
		this.addCommand("comb_glide", "f", { arg msg; combCore.set(\glide, msg[1]) });
		this.addCommand("comb_tooth", "iff", { arg msg;
			var k = (msg[1] - 1).clip(0, 63), j = k div: 16, syn = combTeeth[j];
			syn.seti(\tooth, k % 16, msg[2].clip(0, 1));
			syn.seti(\toothG, k % 16, msg[3]);
			// a group of sixteen teeth with nothing to play is paused, which saves CPU at low densities
			toothGains[k] = msg[3];
			syn.run(toothGains.copyRange(j * 16, j * 16 + 15).any { |v| v.abs > 0 });
		});
		this.addCommand("comb_fb", "f", { arg msg; combCore.set(\combFb, msg[1]) });
		this.addCommand("comb_type", "i", { arg msg; combCore.set(\combType, msg[1]) });
		this.addCommand("comb_on", "i", { arg msg; cGroup.set(\combOn, msg[1]) });
		this.addCommand("slfo_wave", "i", { arg msg; combCore.set(\slfoWave, msg[1]) });
		this.addCommand("slfo_depth", "f", { arg msg; combCore.set(\slfoDepth, msg[1]) });
		this.addCommand("slfo_rate", "f", { arg msg; combCore.set(\slfoRate, msg[1]) });
		this.addCommand("exciter", "i", { arg msg; combCore.set(\exciter, msg[1]) });
		this.addCommand("pluck", "f", { arg msg; combCore.set(\pluckAmp, msg[1], \t_pluck, 1) });
		this.addCommand("ping", "f", { arg msg; srcSyn.set(\pingAmp, msg[1], \t_ping, 1) });

		this.addCommand("routing", "i", { arg msg; this.setRouting(msg[1]) });
		this.addCommand("mix", "f", { arg msg; mixSyn.set(\mix, msg[1]) });
		this.addCommand("balance", "f", { arg msg; [delCore, mixSyn].do(_.set(\balance, msg[1])) });
		this.addCommand("in_gain", "f", { arg msg; srcSyn.set(\inGain, msg[1]) });
		this.addCommand("out_level", "f", { arg msg; mixSyn.set(\outLevel, msg[1]) });
		this.addCommand("source", "i", { arg msg; srcSyn.set(\source, msg[1]) });
		this.addCommand("file", "s", { arg msg; this.loadInto(\bufFile, msg[1].asString) });
		this.addCommand("demo", "s", { arg msg; this.loadInto(\bufDemo, msg[1].asString) });

		// --- polls ---
		[\in_db, \dly_db, \cmb_db, \out_db].do { |name, i|
			var b = Bus.newFrom(pollBus, i, 1);
			this.addPoll(name, { b.getSynchronous });
		};
	}

	setTap { arg i, key, value;
		var k = (i - 1).clip(0, 15);
		delTaps[k div: 4].seti(key, k % 4, value);
	}

	// the comb runs before the delay only when it feeds it
	setRouting { arg r;
		routing = r.asInteger.clip(0, 3);
		[delCore, combCore, mixSyn].do(_.set(\routing, routing));
		if(routing == 1) { cGroup.moveBefore(dGroup) } { cGroup.moveAfter(dGroup) };
	}

	// load a sound file (mono or stereo) and swap it in
	loadInto { arg key, path;
		var s = context.server, nch = 2;
		if(File.exists(path).not) { ("Monsun: file not found " ++ path).postln; ^this };
		SoundFile.use(path, { |f| nch = f.numChannels });
		Buffer.readChannel(s, path, channels: if(nch > 1) { [0, 1] } { [0, 0] }, action: { |b|
			var old = if(key == \bufFile) { bufFile } { bufDemo };
			srcSyn.set(key, b);
			if(key == \bufFile) { bufFile = b } { bufDemo = b };
			old.free;
		});
	}

	free {
		([srcSyn, delCore, combCore, mixSyn] ++ delTaps ++ combTeeth).do(_.free);
		[dGroup, cGroup].do(_.free);
		[dbuf, cbuf, fbbuf, bufFile, bufDemo].do(_.free);
		[srcBus, dBus, cBus, refBus, lfoBus, sumBus, cwBus, sizeBus, pollBus].do(_.free);
	}
}
