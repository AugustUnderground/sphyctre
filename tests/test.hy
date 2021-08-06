(import os)
(import sys)
(import time)
(import pexpect)
(import [numpy :as np])
(import [pandas :as pd])

(import [sphyctre [NutMeg NutPlot SpectreSession]])

(setv test-bench f"tests/proprietary/tb.scs")

(setv session (SpectreSession test-bench))

(setv t0 (time.process-time))
(setv res (session.run-all))
(setv t1 (time.process-time))
(print f"Python session took {(- t1 t0) :.4f}s")

(session.alter "Wcm1" 25e-6)
