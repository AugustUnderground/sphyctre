# sphyctre

[Spectre](https://www.cadence.com/en_US/home/tools/custom-ic-analog-rf-design/circuit-simulation/spectre-simulation-platform.html)
interace for Python written in [hy](https://github.com/hylang/hy).

This is mainly inteded as backend for machine learning implementations and
**not for humans**.

## Installation

After cloning

```bash
$ pip install .
```

## Amplifier Characterization 

```python
from sphyctre import OpAnalyzer

pdk_path = f"some/path/to/pdk"
tb_path  = f"some/path/to/test/bench"

op = OpAnalyzer(tb_path, pdk_path)

performance = op.simulate({"Wcm1": 1e-6, "Ld": 0.5e-6})

print(performance)
print(op.simulation-results)
```

## Getting Started and Examples

For more, see `examples/`.

## TODO
