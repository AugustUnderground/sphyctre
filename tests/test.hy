(import os)
(import sys)
(import time)
(import pexpect)
(import [numpy :as np])
(import [scipy [interpolate]])
(import [pandas :as pd])
(import [matplotlib [pyplot :as plt]])
(import [sphyctre [NutMeg NutPlot OpAnalyzer]])
(import [sb3-contrib [QRDQN TQC]])
(require [hy.contrib.walk [let]]) 
(require [hy.contrib.loop [loop]])
(require [hy.extra.anaphoric [*]])
(import [hy.contrib.pprint [pp pprint]])

(setv pdk-path f"/home/uhlmanny/gonzo/Opt/pdk/x-fab/XKIT/xh035/cadence/v6_6/spectre/v6_6_2/mos"
      tb-path  f"tests/proprietary/sym")

(setv op (OpAnalyzer tb-path pdk))

(setv t0 (time.process-time))
(setv performance (.simulate op {"Wcm1" 1e-6 "Ld" 0.5e-6}))
(setv t1 (time.process-time))
(print f"Took {(- t1 t0) :.4f}s")

(pp performance)
