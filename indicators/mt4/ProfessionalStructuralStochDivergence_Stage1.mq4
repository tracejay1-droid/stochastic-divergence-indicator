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
input int    InpABCMaxBarGap       = 8;
input bool   InpDebugLogs          = true;
input int    InpDebugBarStep       = 50;

double StochMainBuffer[];
double StochSignalBuffer[];
double StochSwingHighBuffer[];
double StochSwingLowBuffer[];
double PriceSwingHighState[];
double PriceSwingLowState[];

string ST2_PREFIX = "PSD_STAGE2_MT4_";

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

void CollectLatestSwings(const int rates_total,
                         const double &highBuf[],
                         const double &lowBuf[],
                         int &bars[],
                         double &vals[],
                         int &types[])
{
   ArrayResize(bars,0);
   ArrayResize(vals,0);
   ArrayResize(types,0);

   for(int i=rates_total-2; i>=1; i--)
   {
      bool hasHigh = (highBuf[i] != EMPTY_VALUE);
      bool hasLow  = (lowBuf[i] != EMPTY_VALUE);
      if(!hasHigh && !hasLow) continue;

      int newSize = ArraySize(bars)+1;
      ArrayResize(bars,newSize);
      ArrayResize(vals,newSize);
      ArrayResize(types,newSize);

      bars[newSize-1] = i;
      if(hasHigh)
      {
         vals[newSize-1] = highBuf[i];
         types[newSize-1] = 1;
      }
      else
      {
         vals[newSize-1] = lowBuf[i];
         types[newSize-1] = -1;
      }
   }
}

bool BuildLatestABC(const int &bars[],
                    const double &vals[],
                    const int &types[],
                    int &aBar,
                    int &bBar,
                    int &cBar,
                    double &aVal,
                    double &bVal,
                    double &cVal)
{
   int count=ArraySize(bars);
   if(count<3) return(false);

   for(int i=count-1; i>=2; i--)
   {
      int iA=i-2;
      int iB=i-1;
      int iC=i;
      if(types[iA]==types[iB] || types[iB]==types[iC])
         continue;

      aBar=bars[iA]; bBar=bars[iB]; cBar=bars[iC];
      aVal=vals[iA]; bVal=vals[iB]; cVal=vals[iC];
      return(true);
   }
   return(false);
}

bool IsAlignedABC(const int pA,const int pB,const int pC,
                  const int sA,const int sB,const int sC)
{
   return(MathAbs(pA-sA)<=InpABCMaxBarGap &&
          MathAbs(pB-sB)<=InpABCMaxBarGap &&
          MathAbs(pC-sC)<=InpABCMaxBarGap);
}

void DeleteStage2Objects()
{
   string keys[] = {
      "P_AB","P_BC","P_A","P_B","P_C",
      "S_AB","S_BC","S_A","S_B","S_C"
   };
   for(int i=0;i<ArraySize(keys);i++)
      ObjectDelete(ST2_PREFIX+keys[i]);
}

void DrawABCSegment(const string name,
                    const int window,
                    const datetime t1,
                    const double v1,
                    const datetime t2,
                    const double v2,
                    const color clr)
{
   ObjectDelete(name);
   ObjectCreate(name,OBJ_TREND,window,t1,v1,t2,v2);
   ObjectSet(name,OBJPROP_COLOR,clr);
   ObjectSet(name,OBJPROP_WIDTH,2);
   ObjectSet(name,OBJPROP_RAY,false);
}

void DrawABCText(const string name,
                 const int window,
                 const datetime t,
                 const double v,
                 const string text,
                 const color clr)
{
   ObjectDelete(name);
   ObjectCreate(name,OBJ_TEXT,window,t,v);
   ObjectSetText(name,text,9,"Arial",clr);
}

void RenderABC(const datetime &time[],
               const int pA,const int pB,const int pC,
               const double pAv,const double pBv,const double pCv,
               const int sA,const int sB,const int sC,
               const double sAv,const double sBv,const double sCv)
{
   DebugPrint("[OnCalculate] Before RenderABC");
   DeleteStage2Objects();

   // Price ABC in main chart window
   DrawABCSegment(ST2_PREFIX+"P_AB",0,time[pA],pAv,time[pB],pBv,clrDodgerBlue);
   DrawABCSegment(ST2_PREFIX+"P_BC",0,time[pB],pBv,time[pC],pCv,clrDodgerBlue);
   DrawABCText(ST2_PREFIX+"P_A",0,time[pA],pAv,"A",clrDodgerBlue);
   DrawABCText(ST2_PREFIX+"P_B",0,time[pB],pBv,"B",clrDodgerBlue);
   DrawABCText(ST2_PREFIX+"P_C",0,time[pC],pCv,"C",clrDodgerBlue);

   // Stochastic ABC in indicator subwindow
   DrawABCSegment(ST2_PREFIX+"S_AB",1,time[sA],sAv,time[sB],sBv,clrGold);
   DrawABCSegment(ST2_PREFIX+"S_BC",1,time[sB],sBv,time[sC],sCv,clrGold);
   DrawABCText(ST2_PREFIX+"S_A",1,time[sA],sAv,"A",clrGold);
   DrawABCText(ST2_PREFIX+"S_B",1,time[sB],sBv,"B",clrGold);
   DrawABCText(ST2_PREFIX+"S_C",1,time[sC],sCv,"C",clrGold);

   DebugPrint("[OnCalculate] After RenderABC");
}

int OnInit()
{
   DebugPrint("[OnInit] Start OnInit");

   IndicatorShortName("Professional Structural Stoch Divergence - Stage2 (MT4)");

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


void OnDeinit(const int reason)
{
   DeleteStage2Objects();
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

   int pBars[]; double pVals[]; int pTypes[];
   int sBars[]; double sVals[]; int sTypes[];
   CollectLatestSwings(rates_total,PriceSwingHighState,PriceSwingLowState,pBars,pVals,pTypes);
   CollectLatestSwings(rates_total,StochSwingHighBuffer,StochSwingLowBuffer,sBars,sVals,sTypes);

   int pA,pB,pC,sA,sB,sC;
   double pAv,pBv,pCv,sAv,sBv,sCv;
   bool pOk=BuildLatestABC(pBars,pVals,pTypes,pA,pB,pC,pAv,pBv,pCv);
   bool sOk=BuildLatestABC(sBars,sVals,sTypes,sA,sB,sC,sAv,sBv,sCv);

   if(pOk && sOk && IsAlignedABC(pA,pB,pC,sA,sB,sC))
   {
      PrintFormat("[DEBUG][MT4][Stage2] ABC aligned. p=(%d,%d,%d) s=(%d,%d,%d)",pA,pB,pC,sA,sB,sC);
      RenderABC(time,pA,pB,pC,pAv,pBv,pCv,sA,sB,sC,sAv,sBv,sCv);
   }
   else
   {
      DebugPrint("[OnCalculate] ABC not ready or not aligned; clearing Stage2 objects");
      DeleteStage2Objects();
   }

   PrintFormat("[DEBUG][MT4][OnCalculate] End return=%d",rates_total);
   return(rates_total);
}
