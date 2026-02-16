# stochastic-divergence-indicator
Professional structural stochastic divergence indicator (MT4 / MT5).

## Deliverables
- `indicators/mt4/ProfessionalStructuralStochDivergence_Stage1.mq4`
- `indicators/mt5/ProfessionalStructuralStochDivergence_Stage1.mq5`

## Current scope
- Stage 1 structural swing engine (price + stochastic impulse/retracement confirmation)
- Stage 2 ABC extraction / labeling and divergence line rendering on price + stochastic
- Stage 3 divergence taxonomy implementation: A1/A2/A3/A4, B1/B2, C1/C2, D1/D2, E1/E2
- Early alert trigger by divergence completion point (B or C by type), once per new divergence
- Dedicated stochastic subwindow output (`#property indicator_separate_window`)
- Always-plotted stochastic main/signal lines (default 5,3,3)
- No WebRequest or internet calls in indicator code
