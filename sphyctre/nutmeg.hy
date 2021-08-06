(import os)
(import re)
(import random)
(import string)
(import [numpy :as np])
(import [pandas :as pd])

(require [hy.contrib.walk [let]])
(require [hy.contrib.loop [loop]])
(require [hy.extra.anaphoric [*]])

(defn _read-next-line-pattern ^str [^bytes raw ^str pattern 
                          &optional ^bool [reverse False]]
  (as-> raw it
    (get it (slice (setx pattern-idx ((if reverse it.rfind it.find)
                                          (.encode pattern)))
                (it.find b"\n" pattern-idx)))
    (.decode it)
    (when it
      (-> it (.split (+ pattern ":"))
             (second)
             (.strip)))))

(defn _read-next-block-pattern ^dict [^bytes raw ^str first-pattern
                                      ^str second-pattern 
                     &optional ^bool [reverse False]]
  (as-> raw it
        (get it (slice (setx fp-idx ((if reverse 
                                         it.rfind 
                                         it.find) 
                                     (.encode first-pattern)))
                       (it.find (.encode second-pattern) fp-idx)))
        (.decode it)
        (.removeprefix it first-pattern)
        (.split it "\n")
        (lfor i it (.strip i))
        (dfor j (lfor i it (.split i "\t")) :if (first j) 
          [(get j 1) 
           { "index" (get j 0) 
             "unit" (-> j (get 2) (.split " ") (first))}])))

(defn _get-analysis-type ^str [^str plot-name]
  (let [analysis-pattern "`(.*?)'"
        analysis-match (re.search analysis-pattern plot-name)]
    (if analysis-match
      (.group analysis-match 1)
      (+ "dummy_" (.join "" (random.sample string.ascii-letters 5))))))

(defclass NutPlot []
  """
  Reprensents a single Plot within a nutmeg file.
  Attributes:
    plot_name:      name of the plot in the file.
    flags:          real | complex
    n_variables:    number of variables (columns).
    n_points:       number of data points (rows).
    variables:      list of variable names and their respective units.
    data:           the data as named numpy array

  Methods:
    as-dataframe:   Returns data as pandas DataFrame.
  """
  (setv _values-id b"\nBinary:\n")

  (defn __init__ [self ^bytes raw-plot] 
    """
    Creates a NutPlot object for the given plot inside a binary raw file.
    """
    (setv self.plot-name    (_read-next-line-pattern raw-plot "Plotname")
          self.flags        (_read-next-line-pattern raw-plot "Flags"))

    (setv self.n-variables  (int (_read-next-line-pattern raw-plot 
                                                          "No. Variables"
                                                          :reverse False))
          self.n-points     (int (_read-next-line-pattern raw-plot 
                                                          "No. Points"
                                                          :reverse False)))

    (setv self.variables    (_read-next-block-pattern raw-plot 
                                                      "Variables:" 
                                                      "Binary:" 
                                                      :reverse True))

    (setv dtypes            (-> {"names"   (list (.keys self.variables)) 
                                 "formats" (* (if (in "complex" self.flags)
                                                  [np.complex128]
                                                  [np.float64]) 
                                              self.n-variables)}
                                (np.dtype)
                                (.newbyteorder ">")))

    (setv raw-data          (get raw-plot (slice (+ (raw-plot.find 
                                                     NutPlot._values-id) 
                                                    (len NutPlot._values-id)) 
                                          None)))

    (setv self.data (np.frombuffer raw-data 
                                   :dtype dtypes 
                                   :count self.n-points)))
  
  (defn as-dataframe [self]
    """
    Convert the named numpy array into a pandas dataframe.
    """
    (pd.DataFrame self.data)))

(defclass NutMeg []
  """
  Reprensents the contents of a binary nutmeg file.
  Attributes:
    title:      title of the netlist.
    date:       date it was created.
    n-plots:    number of plots in the file.
    plots:      dictionary mapping all plots in the file 
                {plot-name : NutPlot, ... }
  Methods:
    plot-dict:  returns a dictionary with pandas DataFrames instead of NutPlot
                Objects.
  """
  (setv _plots-id (re.compile b"Plotname"))

  (defn __init__ [self ^str file-name]
    """
    Creates a NutMeg object for the given binary raw file.
    """
    (unless (os.path.isfile file-name) 
      (raise (FileNotFoundError errno.ENOENT 
                                (os.strerror errno.ENOENT) 
                                file-name)))

    (setv raw-data (with [raw-file (open file-name "rb")]
                      (.read raw-file)))

    (setv self.title (_read-next-line-pattern raw-data "Title")
          self.date  (_read-next-line-pattern raw-data "Date"))

    (setv pex       (-> (setx psx (lfor idx (-> NutMeg._plots-id
                                                (re.compile) 
                                                (.finditer raw-data)) 
                                            (.start idx))) 
                        (rest) (list) (+ [(len raw-data)]))
          raw-plots (lfor (, sx ex) (zip psx pex) 
                          (get raw-data (slice sx ex))))

    (setv self.plots (dfor plt raw-plots 
                           [(_get-analysis-type (_read-next-line-pattern plt "Plotname"))
                            (NutPlot plt)])

          self.n-plots (len self.plots)))

  (defn plot-dict [self]
    """
    Return a dictionary of plots as pandas DataFrames.
    """
    (dfor (, n p) (.items self.plots)
          [n (.as-dataframe p)])))
