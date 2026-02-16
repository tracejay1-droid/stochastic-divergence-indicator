# stochastic-divergence-indicator
Professional structural stochastic divergence indicator (MT4 / MT5).

## Deliverables (Stage 1 stability + debug build)
- `indicators/mt4/ProfessionalStructuralStochDivergence_Stage1.mq4`
- `indicators/mt5/ProfessionalStructuralStochDivergence_Stage1.mq5`

## Current scope
- Stage 1 structural swing engine only (no divergence classification yet)
- Dedicated stochastic subwindow output (`#property indicator_separate_window`)
- Always-plotted stochastic main/signal lines (default 5,3,3)
- Structural swing confirmation for price and stochastic (impulse + retracement)
- Extensive debug logs in MT4/MT5 using `[DEBUG][MT4]` and `[DEBUG][MT5]` tags
- No WebRequest or internet calls in indicator code
