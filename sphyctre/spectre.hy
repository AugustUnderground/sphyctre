(import os)
(import sys)
(import time)
(import pexpect)
(import tempfile)

(import errno)
(import warnings)

(import [numpy :as np])

(import [.nutmeg [NutMeg NutPlot]])

(require [hy.contrib.walk [let]])
(require [hy.contrib.loop [loop]])
(require [hy.extra.anaphoric [*]])

(defn simulate ^NutMeg [^str netlist-path]
  """
  Passes the given netlist path to spectre and reads the results in.
  """
  (let [cmd (.format "spectre {}" netlist-path)
        raw (.format "{}.raw" (-> netlist-path (os.path.splitext) (first)))
        ret (os.system cmd)]
    (if (and (= 0 ret ) (os.path.isfile raw))
      (NutMeg raw)
      (cond [(!= ret 0)
             (raise (IOError errno.EIO (os.strerror errno.EIO) "spectre"))]
             [(os.path.isfile raw)
              (raise (FileNotFoundError errno.ENOENT 
                                       (os.strerror errno.ENOENT) 
                                       raw))]
             [True
              (raise (Exception "Failed to run spectre or read file."))]))))

(defn simulate-netlist ^NutMeg [^str netlist]
  """
  Takes a netlist as text, creates a temporary file and simulates it. The
  results are read in and all temp files will be destroyed.
  """
  (with [temp-netlist (.TemporaryFile tempfile)]
    (temp-netlist.write netlist)
    (simulate tmp)))

(defclass SpectreSession []
  """
  Interactive Spectre Simulation Session
  Attributes:
    net-file:   path to netlist.
    raw-file:   path to raw file.
    shell:      spectre interactive shell
  Methods:
    run_all:    run all analyses specified in the netlist.
    alter:      change the value of a prameter defined in the netlist.
  """

  (setv _prompt-pattern "\r\n>\s"
        _spectre-command "spectre -64"
        _positive ".*\nt"
        _negative ".*\nnil")

  (defn __init__ [self ^str netlist &optional ^str spectre
                       ^float [vs 0.5]   ^float [cl 5e-12]
                       ^float [rl 100e6] ^float [i0 3e-6]
                       ^float [vsup 3.3] ^float [fin 1e3]
                       ^float [dev 1e-4] ]
    """
    Creates a new spectre interactive session with the given netlist.
    """
    (unless (os.path.isfile netlist) 
      (raise (FileNotFoundError errno.ENOENT 
                                (os.strerror errno.ENOENT) 
                                netlist)))

    (setv self.net-file netlist
          self.raw-file f"{(first (os.path.splitext self.net-file))}.raw")

    (setv spectre-command f"{(or spectre SpectreSession._spectre-command)} +interactive {self.net-file}"
          self.shell (pexpect.spawn spectre-command))

    (unless (= (self.shell.expect SpectreSession._prompt-pattern) 0)
      (raise (IOError errno.EIO (os.strerror errno.EIO) "spectre"))))

  (defn _run-command ^bool [self ^str command]
    """
    Internal function for running an arbitrary scl command. Returns True or
    false based on what the previous command returned.
    """
    (self.shell.sendline command)
    (= (self.shell.expect SpectreSession._prompt-pattern) 0))

  (defn _read-results ^NutMeg [self]
    """
    Internal function for reading the results of a simpulation.
    """
    (NutMeg self.raw-file))

  (defn run-all ^NutMeg [self]
    """
    Run all analyses defined in the netlist.
    """
    (self._run-command "(sclRun \"all\")")
    (self._read-results))

  (defn list-parameters []
    """
    List defined parameters in the netlist.
    """
    (raise (NotImplementedError "Check the netlist for available parameters")))

  (defn alter-parameter ^bool [self ^str param ^float value]
    """
    Change a parameter in the netlist. Returns True if successful, False
    otherwise.
    """
    (let [alter-cmd  (.format (+ "(sclSetAttribute "
                                  "(sclGetParameter "
                                    "(sclGetCircuit \"\") "
                                    "\"{}\") "
                                  "\"value\" {})")
                              param value)]
      (self._run-command alter-cmd)))

  (defn __del__ [self]
  """
  Destructor will attempt to close the spectre session.
  """
    (when (.isalive self.shell)
      (self.shell.sendline "(sclQuit)"))
    (when (.isalive self.shell))
      (warnings.warn RuntimeWarning 
        f"Failed to close spectre session cleanly, attempting to force it.")
      (self.shell.close :force True)))
