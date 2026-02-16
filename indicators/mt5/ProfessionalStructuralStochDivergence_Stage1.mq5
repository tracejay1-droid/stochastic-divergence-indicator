#property strict
#property indicator_separate_window
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_plots 4
#property indicator_buffers 6

#property indicator_type1 DRAW_LINE
#property indicator_color1 DeepSkyBlue
#property indicator_label1 "Stoch Main"

#property indicator_type2 DRAW_LINE
#property indicator_color2 Orange
#property indicator_label2 "Stoch Signal"

#property indicator_type3 DRAW_ARROW
#property indicator_color3 LimeGreen
#property indicator_label3 "Stoch Swing High"

#property indicator_type4 DRAW_ARROW
#property indicator_color4 Tomato
#property indicator_label4 "Stoch Swing Low"

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
double PriceSwingHighState[];
double PriceSwingLowState[];

double ATRBuffer[];
double EMAFastBuffer[];
double EMASlowBuffer[];

int atrHandle=INVALID_HANDLE;
int emaFastHandle=INVALID_HANDLE;
int emaSlowHandle=INVALID_HANDLE;
int stochHandle=INVALID_HANDLE;

void DebugPrint(string msg)
{
   if(InpDebugLogs)
      PrintFormat("[DEBUG][MT5] %s | chart=%I64d symbol=%s", msg, ChartID(), _Symbol);
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
      StochSwingHighBuffer[i]=EMPTY_VALUE;
      StochSwingLowBuffer[i]=EMPTY_VALUE;
      PriceSwingHighState[i]=EMPTY_VALUE;
      PriceSwingLowState[i]=EMPTY_VALUE;
   }
   DebugPrint("[OnCalculate] After ResetWorkingBuffers");
}

void EvaluatePriceStructure(const int rates_total,
                            const double &high[],
                            const double &low[],
                            const double &close[])
{
   DebugPrint("[OnCalculate] Before EvaluatePriceStructure");

   int start=rates_total-2;
   int dir=0;
   int extremeBar=start;
   double extreme=close[start];
   double legStart=close[start];

   for(int i=start;i>=1;i--)
   {
      double atr=ATRBuffer[i];
      if(atr<=0.0) continue;

      double atrSum=0.0;
      int count=0;
      for(int n=0;n<10 && (i+n)<rates_total;n++)
      {
         atrSum += ATRBuffer[i+n];
         count++;
      }
      double atrAvg=(count>0?atrSum/count:atr);

      double emaFast=EMAFastBuffer[i];
      double emaSlow=EMASlowBuffer[i];
      double emaFastPrev=EMAFastBuffer[i+1];

      bool compressed=(atrAvg>0.0 && atr < atrAvg*InpCompressionFactor);
      bool emaQualified=(MathAbs(emaFast-emaSlow)>=atr*InpEMASepATRMult || MathAbs(emaFast-emaFastPrev)>=atr*InpEMASlopeATRMult);

      if(ShouldLogBar(i))
         PrintFormat("[DEBUG][MT5][PriceLoop] i=%d atr=%.5f atrAvg=%.5f dir=%d close=%.5f emaFast=%.5f emaSlow=%.5f | chart=%I64d symbol=%s",i,atr,atrAvg,dir,close[i],emaFast,emaSlow,ChartID(),_Symbol);

      if(dir==0)
      {
         legStart=close[i+1];
         extreme=close[i+1];
         extremeBar=i+1;

         if(!compressed && emaQualified)
         {
            if(close[i]-legStart>=atr*InpImpulseATRMult)
            {
               dir=1;
               extreme=high[i];
               extremeBar=i;
            }
            else if(legStart-close[i]>=atr*InpImpulseATRMult)
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

         if(extreme-low[i]>=atr*InpRetraceATRMult)
         {
            PriceSwingHighState[extremeBar]=high[extremeBar];
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

         if(high[i]-extreme>=atr*InpRetraceATRMult)
         {
            PriceSwingLowState[extremeBar]=low[extremeBar];
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

   int start=rates_total-2;
   int dir=0;
   int extremeBar=start;
   double extreme=StochMainBuffer[start];
   double legStart=StochMainBuffer[start];

   for(int i=start;i>=1;i--)
   {
      double sv=StochMainBuffer[i];
      double svPrev=StochMainBuffer[i+1];

      if(ShouldLogBar(i))
         PrintFormat("[DEBUG][MT5][StochLoop] i=%d sv=%.2f svPrev=%.2f dir=%d | chart=%I64d symbol=%s",i,sv,svPrev,dir,ChartID(),_Symbol);

      if(dir==0)
      {
         legStart=svPrev;
         extreme=svPrev;
         extremeBar=i+1;

         if(sv-legStart>=InpStochImpulse)
         {
            dir=1;
            extreme=sv;
            extremeBar=i;
         }
         else if(legStart-sv>=InpStochImpulse)
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

         if(extreme-sv>=InpStochRetrace)
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

         if(sv-extreme>=InpStochRetrace)
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

void RedrawPriceSwingObjects(const int rates_total)
{
   // Stage 1: no object drawing yet, only debug checkpoint requested.
   DebugPrint("[OnCalculate] RedrawPriceSwingObjects checkpoint reached");
}

int OnInit()
{
   DebugPrint("[OnInit] Start OnInit");

   IndicatorSetString(INDICATOR_SHORTNAME,"Professional Structural Stoch Divergence - Stage1 (MT5)");

   SetIndexBuffer(0,StochMainBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,StochSignalBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,StochSwingHighBuffer,INDICATOR_DATA);
   SetIndexBuffer(3,StochSwingLowBuffer,INDICATOR_DATA);
   SetIndexBuffer(4,PriceSwingHighState,INDICATOR_CALCULATIONS);
   SetIndexBuffer(5,PriceSwingLowState,INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(2,PLOT_ARROW,159);
   PlotIndexSetInteger(3,PLOT_ARROW,159);
   PlotIndexSetDouble(2,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(3,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   ArraySetAsSeries(StochMainBuffer,true);
   ArraySetAsSeries(StochSignalBuffer,true);
   ArraySetAsSeries(StochSwingHighBuffer,true);
   ArraySetAsSeries(StochSwingLowBuffer,true);
   ArraySetAsSeries(PriceSwingHighState,true);
   ArraySetAsSeries(PriceSwingLowState,true);
   ArraySetAsSeries(ATRBuffer,true);
   ArraySetAsSeries(EMAFastBuffer,true);
   ArraySetAsSeries(EMASlowBuffer,true);

   atrHandle=iATR(_Symbol,_Period,InpATRPeriod);
   emaFastHandle=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   emaSlowHandle=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   stochHandle=iStochastic(_Symbol,_Period,InpKPeriod,InpDPeriod,InpSlowing,MODE_SMA,STO_LOWHIGH);

   PrintFormat("[DEBUG][MT5][OnInit] handles atr=%d emaFast=%d emaSlow=%d stoch=%d chart=%I64d symbol=%s",atrHandle,emaFastHandle,emaSlowHandle,stochHandle,ChartID(),_Symbol);

   if(atrHandle==INVALID_HANDLE || emaFastHandle==INVALID_HANDLE || emaSlowHandle==INVALID_HANDLE || stochHandle==INVALID_HANDLE)
   {
      PrintFormat("[DEBUG][MT5][OnInit] INIT_FAILED due to invalid handle(s). chart=%I64d symbol=%s",ChartID(),_Symbol);
      return(INIT_FAILED);
   }

   DebugPrint("[OnInit] After setting indicator buffers");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(emaFastHandle!=INVALID_HANDLE) IndicatorRelease(emaFastHandle);
   if(emaSlowHandle!=INVALID_HANDLE) IndicatorRelease(emaSlowHandle);
   if(stochHandle!=INVALID_HANDLE) IndicatorRelease(stochHandle);
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
   PrintFormat("[DEBUG][MT5][OnCalculate] Start rates_total=%d prev_calculated=%d chart=%I64d symbol=%s",rates_total,prev_calculated,ChartID(),_Symbol);

   int minBars=MathMax(MathMax(InpSlowEMA,InpATRPeriod),InpKPeriod+InpDPeriod+InpSlowing)+20;
   if(rates_total < minBars)
   {
      PrintFormat("[DEBUG][MT5][OnCalculate] Early exit: rates_total=%d < minBars=%d chart=%I64d symbol=%s",rates_total,minBars,ChartID(),_Symbol);
      return(0);
   }

   ArrayResize(ATRBuffer,rates_total);
   ArrayResize(EMAFastBuffer,rates_total);
   ArrayResize(EMASlowBuffer,rates_total);

   int cAtr=CopyBuffer(atrHandle,0,0,rates_total,ATRBuffer);
   int cFast=CopyBuffer(emaFastHandle,0,0,rates_total,EMAFastBuffer);
   int cSlow=CopyBuffer(emaSlowHandle,0,0,rates_total,EMASlowBuffer);
   int cStMain=CopyBuffer(stochHandle,0,0,rates_total,StochMainBuffer);
   int cStSig=CopyBuffer(stochHandle,1,0,rates_total,StochSignalBuffer);

   PrintFormat("[DEBUG][MT5][OnCalculate] After CopyBuffer cAtr=%d cFast=%d cSlow=%d cStMain=%d cStSig=%d chart=%I64d symbol=%s",cAtr,cFast,cSlow,cStMain,cStSig,ChartID(),_Symbol);

   if(cAtr<rates_total || cFast<rates_total || cSlow<rates_total || cStMain<rates_total || cStSig<rates_total)
   {
      PrintFormat("[DEBUG][MT5][OnCalculate] CopyBuffer failure/partial copy. rates_total=%d chart=%I64d symbol=%s",rates_total,ChartID(),_Symbol);
      return(prev_calculated);
   }

   ResetWorkingBuffers(rates_total);
   EvaluatePriceStructure(rates_total,high,low,close);
   EvaluateStochasticStructure(rates_total);

   DebugPrint("[OnCalculate] Before RedrawPriceSwingObjects");
   RedrawPriceSwingObjects(rates_total);

   PrintFormat("[DEBUG][MT5][OnCalculate] End return=%d chart=%I64d symbol=%s",rates_total,ChartID(),_Symbol);
   return(rates_total);
}
