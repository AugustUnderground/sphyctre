(import [numpy :as np])
(import [pandas :as pd])
(import [scipy [interpolate]])

(import [.nutmeg [NutMeg NutPlot]])
(import [.spectre [SpectreInteractive]])

(require [hy.contrib.walk [let]])
(require [hy.contrib.loop [loop]])
(require [hy.extra.anaphoric [*]])

(defn _find [^pd.DataFrame df ^str col ^float val]
  (-> df (get col) (.sub val) (.abs) (.idxmin)))

(defclass OpAnalyzer []
  (defn __init__ [self ^str test-bench ^str pdk-path]
    (setv self.test-bench f"{test-bench}/tb.scs"
          self.dc-test-bench f"{test-bench}/dc.scs"
          self.pdk-path pdk-path)

    (setv self.tb-session (SpectreInteractive self.test-bench 
                                              :include-dir pdk-path)
          self.dc-session (SpectreInteractive self.dc-test-bench 
                                              :include-dir pdk-path))

    (setv self.simulation-results {}))

  (defn characterize-operatingpoint ^dict [self]
    (let [ dc-perf (-> self.dc-session (.run-all) (.values) (first)) ]
      (.update self.simulation-results {"dc" dc-perf})
      (-> dc-perf (.to-dict "records") (first))))

  (defn characterize-performance ^dict [self
                     &optional ^float [vs 0.5] ^float [vs-ul 0.9] ^float [vs-ll 0.1]
                               ^float [cl 5e-12] ^float [rl 100e6] ^float [i0 3e-6] 
                               ^float [vsup 3.3] ^float [fin 1e3] ^float [dev 1e-4]]
    (let [plots (.run-all self.tb-session)
          _ (.update self.simulation-results plots)
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
          f3dB (. (get stb.freq (_find stb "gain" A3dB)) real)
          f0dB (. (get stb.freq (_find stb "gain" 0.0)) real)
          PM (get stb.phase (_find stb "freq" f0dB))
          GM (get stb.gain (_find stb "phase" 0.0))

          ;; Transient Analysis
          time (-> plots (get "tran" "time") (. values))
          out (-> plots (get "tran" "OUT") (. values))
          lo (- (* vs-ll vs) (* vs 0.5))
          hi (- (* vs-ul vs) (* vs 0.5))
          tran (get plots "tran")
          mid-point (/ (.max tran.time) 2)

          rising (get tran (& (<= tran.time mid-point) 
                              (>= tran.OUT lo)
                              (<= tran.OUT hi))
                           ["time"])

          ;_ (print (-> rising (. values) (np.max :initial -1.0)))

          sr-rising (/ (- hi lo) 
                       (- (-> rising (. values) (np.max :initial 1.0))
                          (-> rising (. values) (np.min :initial 0.0))))
                          
          falling (get tran (& (> tran.time mid-point) 
                               (>= tran.OUT lo)
                               (<= tran.OUT hi))
                            ["time"])

          ;_ (print (-> falling (. values) (np.min :initial -1.0)))

          sr-falling (/ (- hi lo) 
                        (- (-> falling (. values) (np.max :initial 1.0))
                           (-> falling (. values) (np.min :initial 0.0))))

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
          ;vn-100Hz (get noise.out (_find noise "freq" 1e2))

          ;; DC Analysis: out swing
          dc1 (get plots "dc1")
          out-dc (- dc1.OUT (get dc1.OUT (-> dc1 (. vid) (.sub 0.0) (.abs) (.idxmin))))
          dev-rel (/ (np.abs (- out-dc dc1.OUT_IDEAL)) vsup)
          vil-dc (-> dev-rel (get (<= dc1.vid 0.0)) (.sub dev) (.abs) (.idxmin))
          vih-dc (-> dev-rel (get (>= dc1.vid 0.0)) (.sub dev) (.abs) (.idxmin))
          vol-dc (+ (get out-dc vil-dc) (/ vsup 2.0))
          voh-dc (+ (get out-dc vih-dc) (/ vsup 2.0))

          ;; XF Analysis
          xf (get plots "xf")
          vid-db (-> xf (. VID) (np.abs) (np.log10) (* 20.0))
          vicm-db (-> xf (. VICM) (np.abs) (np.log10) (* 20.0))
          vsupp-db (-> xf (. VSUPP) (np.abs) (np.log10) (* 20.0))
          vsupn-db (-> xf (. VSUPN) (np.abs) (np.log10) (* 20.0))
          psrr-p (first (. (- vid-db vsupp-db) values))
          psrr-n (first (. (- vid-db vsupn-db) values))
          cmrr (first (. (- vid-db vicm-db) values))

          ;; AC Analysis
          ac (get plots "ac")
          out-ac (-> ac (. OUT) (np.abs) (np.log10) (* 20))
          vil-ac (. (+ (get ac.vicm (.idxmin (.abs (.sub (get out-ac (<= ac.vicm 0.0)) 
                                                      (- A0dB 3))))) 
                       (/ vsup 2.0)) 
                    real)
          vih-ac (. (+ (get ac.vicm (.idxmin (.abs (.sub (get out-ac (>= ac.vicm 0.0)) 
                                                      (- A0dB 3))))) 
                       (/ vsup 2.0))
                    real)

          ;; DC Analysis
          i-out-min (-> plots (get "dc3" "DUT:O") (. values) (first))
          i-out-max (-> plots (get "dc4" "DUT:O") (. values) (first))

          ;; Performance dictionary
          performance {"voff_stat"  voff-stat
                       "voff_sys"   voff-syst
                       "a_0"        A0dB
                       "ugbw"       f0dB
                       "pm"         PM
                       "gm"         GM
                       "sr_r"       sr-rising
                       "sr_f"       sr-falling
                       "vn_1Hz"     vn-1Hz
                       "vn_10Hz"    vn-10Hz
                       "vn_100Hz"   vn-100Hz
                       "vn_1kHz"    vn-1kHz
                       "vn_10kHz"   vn-10kHz
                       "vn_100kHz"  vn-100kHz
                       "v_ol"       vol-dc
                       "v_oh"       voh-dc
                       "v_il"       vil-ac
                       "v_ih"       vih-ac
                       "psrr_n"     psrr-n
                       "psrr_p"     psrr-p
                       "cmrr"       cmrr
                       "i_out_max"  i-out-max
                       "i_out_min"  i-out-min}]

    ;; Make sure no NaNs, or Infs are in the results
    (dfor (, p v) (.items performance) 
      [p (np.nan-to-num v)])))

  (defn evaluate-performance [self]
    (| (.characterize-performance self)
       (.characterize-operatingpoint self)))

  (defn set-parameter [self ^str parameter ^float value]
    ((juxt self.tb-session.alter-parameter self.dc-session.alter-parameter)
        parameter value))

  (defn simulate ^dict [self ^dict parameters]
    (when parameters
      (lfor (, p v) (.items parameters) (self.set-parameter p v)))
    (.evaluate-performance self)))


