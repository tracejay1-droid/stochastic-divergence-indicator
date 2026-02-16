# stochastic-divergence-indicator
Professional structural stochastic divergence indicator (MT4 / MT5).

## Current implementation
- `StructuralStochasticDivergence_Stage1.mq4`
- `StructuralStochasticDivergence_Stage1.mq5`

This repository is currently at **Stage 2 – ABC Structure**:
- Stage 1 structural swing engine for price (ATR impulse/retracement with EMA state filter)
- Stage 1 structural swing engine for stochastic momentum (impulse/retracement)
- Stage 2 ABC assignment from the latest three confirmed structural swings
- Stage 2 A→B and B→C trendline drawing for both price and stochastic, with bar-distance alignment gating
- No fractals, no ZigZag, no divergence classification, and no alerting yet
