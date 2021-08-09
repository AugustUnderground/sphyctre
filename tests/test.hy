(import os)
(import sys)
(import time)
(import pexpect)
(import [numpy :as np])
(import [scipy [interpolate]])
(import [pandas :as pd])
(import [matplotlib [pyplot :as plt]])

(import [sphyctre [NutMeg NutPlot SpectreSession]])

(require [hy.contrib.walk [let]])
(require [hy.contrib.loop [loop]])
(require [hy.extra.anaphoric [*]])

(setv test-bench f"tests/proprietary/tb.scs")
(setv session (SpectreSession test-bench))

(defn find [^pd.DataFrame df ^str col ^float val]
  (-> df (get col) (.sub val) (.abs) (.idxmin)))

(defn sim [session]
  (let [plots (-> session (.run-all) (.plot-dict))
        ;; Constants (these have to align with netlist!)
        vs 0.5 cl 5e-12 rl 100e6 i0 3e-6 vsup 3.3 fin 1e3 dev 1e-4
        ;; DC Match Analysis
        dc-match-key (first (filter #%(in "dummy" %1) (.keys plots)))
        voff-stat (first (. (get plots dc-match-key "totalOutput.sigmaOut") values))
        voff-syst (first (. (get plots dc-match-key "totalOutput.dcOp") values))
        ;; Stability Analysis
        stb (get plots "stb")
        _ (setv (get stb "gain") (-> stb (. loopGain) (np.abs) (np.log10) (* 20))
                (get stb "phase") (-> stb (. loopGain) (np.angle :deg True)))
        A0dB (-> stb (. gain) (. values) (first))
        A3dB (- A0dB 3)
        f3dB (. (get stb.freq (find stb "gain" A3dB)) real)
        f0dB (. (get stb.freq (find stb "gain" 0.0)) real)
        PM (get stb.phase (find stb "freq" f0dB))
        GM (get stb.gain (find stb "phase" 0.0))
        ;; Transient Analysis
        time (-> plots (get "tran" "time") (. values))
        out (-> plots (get "tran" "OUT") (. values))
        lo (- (* 0.1 vs) (* vs 0.5))
        hi (- (* 0.9 vs) (* vs 0.5))
        tran (get plots "tran")
        mid-point (/ (.max tran.time) 2)
        rising (get tran (& (<= tran.time mid-point) 
                            (>= tran.OUT lo)
                            (<= tran.OUT hi))
                         ["time"])
        sr-rising (/ (- hi lo) 
                     (- (-> rising (. values) (.max))
                        (-> rising (. values) (.min))))
        falling (get tran (& (> tran.time mid-point) 
                             (>= tran.OUT lo)
                             (<= tran.OUT hi))
                          ["time"])
        sr-falling (/ (- hi lo) 
                      (- (-> falling (. values) (.max))
                         (-> falling (. values) (.min))))
        ;; Noise Analysis
        noise (get plots "noise")
        (, vn-1Hz
           vn-10Hz
           vn-100Hz
           vn-1kHz
           vn-10kHz
           vn-100kHz) (interpolate.pchip-interpolate noise.freq.values 
                                                     noise.out.values 
                                                     [1e0 1e1 1e2 1e3 1e4 1e5])
        ;vn-100Hz (get noise.out (find noise "freq" 1e2))
        ;; DC Analysis: out swing
        dc1 (get plots "dc1")
        out-dc (- dc1.OUT (get dc1.OUT (-> dc1 (. vid) (.sub 0.0) (.abs) (.idxmin))))
        dev-rel (/ (np.abs (- out-dc dc1.OUT_IDEAL)) vsup)
        vil-dc (-> dev-rel (get (<= dc1.vid 0.0)) (.sub dev) (.abs) (.idxmin))
        vih-dc (-> dev-rel (get (>= dc1.vid 0.0)) (.sub dev) (.abs) (.idxmin))
        vol-dc (+ (get out-dc vil-dc) (/ vsup 2))
        voh-dc (+ (get out-dc vih-dc) (/ vsup 2))
        ;; XF Analysis
        xf (get plots "xf")
        vid-db (-> xf (. VID) (np.abs) (np.log10) (* 20))
        vicm-db (-> xf (. VICM) (np.abs) (np.log10) (* 20))
        vsupp-db (-> xf (. VSUPP) (np.abs) (np.log10) (* 20))
        vsupn-db (-> xf (. VSUPN) (np.abs) (np.log10) (* 20))
        psrr-p (first (. (- vid-db vsupp-db) values))
        psrr-n (first (. (- vid-db vsupn-db) values))
        cmrr (first (. (- vid-db vicm-db) values))
        ;; AC Analysis
        ac (get plots "ac")
        out-ac (-> ac (. OUT) (np.abs) (np.log10) (* 20))
        vil-ac (. (+ (get ac.vicm (.idxmin (.abs (.sub (get out-ac (<= ac.vicm 0.0)) 
                                                    (- A0dB 3))))) 
                     (/ vsup 2)) 
                  real)
        vih-ac (. (+ (get ac.vicm (.idxmin (.abs (.sub (get out-ac (>= ac.vicm 0.0)) 
                                                    (- A0dB 3))))) 
                     (/ vsup 2))
                  real)
        ;; DC Analysis
        i-out-min (-> plots (get "dc3" "DUT:O") (. values) (first))
        i-out-max (-> plots (get "dc4" "DUT:O") (. values) (first))]
  {"voff-stat"  voff-stat
   "voff-syst"  voff-syst
   "A0dB"       A0dB
   "ugbw"       f0dB
   "PM"         PM
   "GM"         GM
   "SR-r"       sr-rising
   "SR-f"       sr-falling
   "vn-1Hz"     vn-1Hz
   "vn-10Hz"    vn-10Hz
   "vn-100Hz"   vn-100Hz
   "vn-1kHz"    vn-1kHz
   "vn-10kHz"   vn-10kHz
   "vn-100kHz"  vn-100kHz
   "vo-lo"      vol-dc
   "vo-hi"      voh-dc
   "vi-lo"      vil-ac
   "vi-hi"      vih-ac
   "psrr-n"     psrr-n
   "psrr-p"     psrr-p
   "cmrr"       cmrr
   "i-out-max"  i-out-max
   "i-out-min"  i-out-min}))


(setv t0 (time.process-time))
(setv performance (sim session))
;(setv plots (-> session (.run-all) (.plot-dict)))
(setv t1 (time.process-time))
(print f"Python session took {(- t1 t0) :.4f}s")




(setv (, fig ax) (.subplots plt))
(ax.plot ac.vicm out-ac
         :label "outswing")
;(ax.plot (list (rest (-> res (get "tran" "time") (. values))))
;         (/ (np.diff (-> res (get "tran" "OUT") (. values)))
;            (np.diff (-> res (get "tran" "time") (. values))))
;         :label "diff")
(ax.axhline :y dev)
(ax.set-xlabel "Vid [V]")
(ax.set-ylabel "dev [V]")
(ax.set-title "Test Plots")
;(ax.legend True)
(ax.grid "on")
;(ax.set-xscale "log")
(plt.show)

(setv t0 (time.process-time))
(setv res (sim))
(setv t1 (time.process-time))
(print f"Python session took {(- t1 t0) :.4f}s")

(session.alter "Wcm1" 25e-6)
