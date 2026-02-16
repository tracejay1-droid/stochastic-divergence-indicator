# stochastic-divergence-indicator
Professional structural stochastic divergence indicator (MT4 / MT5).

## Deliverables
- `indicators/mt4/ProfessionalStructuralStochDivergence_Stage1.mq4`
- `indicators/mt5/ProfessionalStructuralStochDivergence_Stage1.mq5`

## Current scope
- Stage 1 structural swing engine (price + stochastic impulse/retracement confirmation)
- Stage 2 ABC extraction from confirmed swings (A/B/C sequence selection)
- Stage 2 time alignment gate between price and stochastic ABC points (`InpABCMaxBarGap`)
- Stage 2 ABC drawing on chart:
  - Price ABC (A→B and B→C + A/B/C labels) in main window
  - Stochastic ABC (A→B and B→C + A/B/C labels) in indicator subwindow
- Dedicated stochastic subwindow output (`#property indicator_separate_window`)
- Always-plotted stochastic main/signal lines (default 5,3,3)
- Extensive debug logs in MT4/MT5 using `[DEBUG][MT4]` and `[DEBUG][MT5]` tags
- No WebRequest or internet calls in indicator code
