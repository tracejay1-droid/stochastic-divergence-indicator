#property strict
#property indicator_separate_window
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_buffers 6
#property indicator_color1 DeepSkyBlue
#property indicator_color2 Orange
#property indicator_color3 LimeGreen
#property indicator_color4 Tomato
#property indicator_color5 clrNONE
#property indicator_color6 clrNONE

input int    InpKPeriod            = 5;
input int    InpDPeriod            = 3;
input int    InpSlowing            = 3;
input int    InpATRPeriod          = 14;
input int    InpFastEMA            = 21;
input int    InpSlowEMA            = 55;
input double InpImpulseATRMult     = 1.20;
input double InpRetraceATRMult     = 0.70;
input double InpCompressionFactor  = 0.75;
input double InpEMASepATRMult      = 0.10;
input double InpEMASlopeATRMult    = 0.05;
input double InpStochImpulse       = 18.0;
input double InpStochRetrace       = 10.0;
input bool   InpDebugLogs          = true;
input int    InpDebugBarStep       = 50;

double StochMainBuffer[];
double StochSignalBuffer[];
double StochSwingHighBuffer[];
double StochSwingLowBuffer[];
double PriceSwingHighState[]; // internal state buffers
double PriceSwingLowState[];

void DebugPrint(string msg)
{
   if(InpDebugLogs)
      Print("[DEBUG][MT4] ", msg);
}

bool ShouldLogBar(const int i)
{
   if(!InpDebugLogs) return(false);
   if(InpDebugBarStep <= 0) return(true);
   return((i % InpDebugBarStep) == 0 || i < 5);
}

void ResetWorkingBuffers(const int rates_total)
{
   DebugPrint("[OnCalculate] Before ResetWorkingBuffers");
   for(int i=0;i<rates_total;i++)
   {
      StochSwingHighBuffer[i] = EMPTY_VALUE;
      StochSwingLowBuffer[i]  = EMPTY_VALUE;
      PriceSwingHighState[i]  = EMPTY_VALUE;
      PriceSwingLowState[i]   = EMPTY_VALUE;
   }
   DebugPrint("[OnCalculate] After ResetWorkingBuffers");
}

void EvaluatePriceStructure(const int rates_total,
                            const double &high[],
                            const double &low[],
                            const double &close[])
{
   DebugPrint("[OnCalculate] Before EvaluatePriceStructure");

   int start = rates_total - 2;
   int dir = 0;
   int extremeBar = start;
   double extreme = close[start];
   double legStart = close[start];

   for(int i=start; i>=1; i--)
   {
      double atr = iATR(NULL,0,InpATRPeriod,i);
      if(atr<=0.0) continue;

      double atrAvg = 0.0;
      int n = 0;
      for(n=0; n<10 && (i+n)<rates_total; n++)
         atrAvg += iATR(NULL,0,InpATRPeriod,i+n);
      if(n>0) atrAvg /= n;

      double emaFast = iMA(NULL,0,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,i);
      double emaSlow = iMA(NULL,0,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,i);
      double emaFastPrev = iMA(NULL,0,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,i+1);

      bool compressed = (atrAvg>0.0 && atr < atrAvg*InpCompressionFactor);
      bool emaQualified = (MathAbs(emaFast-emaSlow) >= atr*InpEMASepATRMult || MathAbs(emaFast-emaFastPrev) >= atr*InpEMASlopeATRMult);

      if(ShouldLogBar(i))
         PrintFormat("[DEBUG][MT4][PriceLoop] i=%d atr=%.5f atrAvg=%.5f dir=%d close=%.5f emaFast=%.5f emaSlow=%.5f",i,atr,atrAvg,dir,close[i],emaFast,emaSlow);

      if(dir==0)
      {
         legStart = close[i+1];
         extreme = close[i+1];
         extremeBar = i+1;

         if(!compressed && emaQualified)
         {
            if(close[i]-legStart >= atr*InpImpulseATRMult)
            {
               dir=1;
               extreme=high[i];
               extremeBar=i;
            }
            else if(legStart-close[i] >= atr*InpImpulseATRMult)
            {
               dir=-1;
               extreme=low[i];
               extremeBar=i;
            }
         }
      }
      else if(dir==1)
      {
         if(high[i]>extreme)
         {
            extreme=high[i];
            extremeBar=i;
         }

         if(extreme-low[i] >= atr*InpRetraceATRMult)
         {
            PriceSwingHighState[extremeBar] = high[extremeBar];
            dir=-1;
            legStart=extreme;
            extreme=low[i];
            extremeBar=i;
         }
      }
      else
      {
         if(low[i]<extreme)
         {
            extreme=low[i];
            extremeBar=i;
         }

         if(high[i]-extreme >= atr*InpRetraceATRMult)
         {
            PriceSwingLowState[extremeBar] = low[extremeBar];
            dir=1;
            legStart=extreme;
            extreme=high[i];
            extremeBar=i;
         }
      }
   }

   DebugPrint("[OnCalculate] After EvaluatePriceStructure");
}

void EvaluateStochasticStructure(const int rates_total)
{
   DebugPrint("[OnCalculate] Before EvaluateStochasticStructure");

   int start = rates_total - 2;
   int dir = 0;
   int extremeBar = start;
   double extreme = StochMainBuffer[start];
   double legStart = StochMainBuffer[start];

   for(int i=start; i>=1; i--)
   {
      double sv = StochMainBuffer[i];
      double svPrev = StochMainBuffer[i+1];

      if(ShouldLogBar(i))
         PrintFormat("[DEBUG][MT4][StochLoop] i=%d sv=%.2f svPrev=%.2f dir=%d",i,sv,svPrev,dir);

      if(dir==0)
      {
         legStart=svPrev;
         extreme=svPrev;
         extremeBar=i+1;

         if(sv-legStart >= InpStochImpulse)
         {
            dir=1;
            extreme=sv;
            extremeBar=i;
         }
         else if(legStart-sv >= InpStochImpulse)
         {
            dir=-1;
            extreme=sv;
            extremeBar=i;
         }
      }
      else if(dir==1)
      {
         if(sv>extreme)
         {
            extreme=sv;
            extremeBar=i;
         }

         if(extreme-sv >= InpStochRetrace)
         {
            StochSwingHighBuffer[extremeBar]=extreme;
            dir=-1;
            legStart=extreme;
            extreme=sv;
            extremeBar=i;
         }
      }
      else
      {
         if(sv<extreme)
         {
            extreme=sv;
            extremeBar=i;
         }

         if(sv-extreme >= InpStochRetrace)
         {
            StochSwingLowBuffer[extremeBar]=extreme;
            dir=1;
            legStart=extreme;
            extreme=sv;
            extremeBar=i;
         }
      }
   }

   DebugPrint("[OnCalculate] After EvaluateStochasticStructure");
}

int OnInit()
{
   DebugPrint("[OnInit] Start OnInit");

   IndicatorShortName("Professional Structural Stoch Divergence - Stage1 (MT4)");

   SetIndexBuffer(0,StochMainBuffer);
   SetIndexStyle(0,DRAW_LINE,STYLE_SOLID,1,clrDeepSkyBlue);
   SetIndexLabel(0,"Stoch Main");

   SetIndexBuffer(1,StochSignalBuffer);
   SetIndexStyle(1,DRAW_LINE,STYLE_SOLID,1,clrOrange);
   SetIndexLabel(1,"Stoch Signal");

   SetIndexBuffer(2,StochSwingHighBuffer);
   SetIndexStyle(2,DRAW_ARROW,STYLE_SOLID,1,clrLimeGreen);
   SetIndexArrow(2,159);
   SetIndexLabel(2,"Stoch Swing High");

   SetIndexBuffer(3,StochSwingLowBuffer);
   SetIndexStyle(3,DRAW_ARROW,STYLE_SOLID,1,clrTomato);
   SetIndexArrow(3,159);
   SetIndexLabel(3,"Stoch Swing Low");

   SetIndexBuffer(4,PriceSwingHighState);
   SetIndexStyle(4,DRAW_NONE);

   SetIndexBuffer(5,PriceSwingLowState);
   SetIndexStyle(5,DRAW_NONE);

   SetIndexEmptyValue(2,EMPTY_VALUE);
   SetIndexEmptyValue(3,EMPTY_VALUE);

   DebugPrint("[OnInit] After setting indicator buffers");
   return(INIT_SUCCEEDED);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   PrintFormat("[DEBUG][MT4][OnCalculate] Start rates_total=%d prev_calculated=%d",rates_total,prev_calculated);

   int minBars = MathMax(MathMax(InpSlowEMA,InpATRPeriod),InpKPeriod+InpDPeriod+InpSlowing) + 20;
   if(rates_total < minBars)
   {
      PrintFormat("[DEBUG][MT4][OnCalculate] Early exit: rates_total=%d < minBars=%d",rates_total,minBars);
      return(0);
   }

   for(int i=0;i<rates_total;i++)
   {
      StochMainBuffer[i]=iStochastic(NULL,0,InpKPeriod,InpDPeriod,InpSlowing,MODE_SMA,0,MODE_MAIN,i);
      StochSignalBuffer[i]=iStochastic(NULL,0,InpKPeriod,InpDPeriod,InpSlowing,MODE_SMA,0,MODE_SIGNAL,i);
   }

   ResetWorkingBuffers(rates_total);
   EvaluatePriceStructure(rates_total,high,low,close);
   EvaluateStochasticStructure(rates_total);

   PrintFormat("[DEBUG][MT4][OnCalculate] End return=%d",rates_total);
   return(rates_total);
}
