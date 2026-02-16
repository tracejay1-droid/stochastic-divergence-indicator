#property strict
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_color1 DodgerBlue
#property indicator_color2 Crimson
#property indicator_color3 LimeGreen
#property indicator_color4 OrangeRed
#property indicator_color5 SlateBlue
#property indicator_color6 Tomato

input int    InpKPeriod=5;
input int    InpDPeriod=3;
input int    InpSlowing=3;
input int    InpATRPeriod=14;
input int    InpFastEMA=21;
input int    InpSlowEMA=55;
input double InpImpulseATRMult=1.20;
input double InpRetraceATRMult=0.70;
input double InpCompressionFactor=0.75;
input double InpEMASepATRMult=0.10;
input double InpEMASlopeATRMult=0.05;
input double InpStochImpulse=18.0;
input double InpStochRetrace=10.0;
input int    InpABCAlignmentBars=8;

// Stage 1 markers
double PriceSwingHighBuffer[];
double PriceSwingLowBuffer[];
double StochSwingHighBuffer[];
double StochSwingLowBuffer[];

// Stage 0 continuity
double StochMainBuffer[];
double StochSignalBuffer[];

string PREFIX="SSD_STAGE2_MT4_";

void ClearABCObjects()
{
   string ids[] = {
      "PRICE_AB","PRICE_BC","STOCH_AB","STOCH_BC",
      "PRICE_A","PRICE_B","PRICE_C","STOCH_A","STOCH_B","STOCH_C"
   };
   for(int i=0;i<ArraySize(ids);i++)
      ObjectDelete(PREFIX+ids[i]);
}

void DrawABCLine(string id,datetime t1,double p1,datetime t2,double p2,color clr,int width)
{
   string name=PREFIX+id;
   if(ObjectFind(name)>=0)
      ObjectDelete(name);
   ObjectCreate(name,OBJ_TREND,0,t1,p1,t2,p2);
   ObjectSet(name,OBJPROP_COLOR,clr);
   ObjectSet(name,OBJPROP_WIDTH,width);
   ObjectSet(name,OBJPROP_RAY,false);
}

void DrawABCLabel(string id,datetime t,double p,string txt,color clr)
{
   string name=PREFIX+id;
   if(ObjectFind(name)>=0)
      ObjectDelete(name);
   ObjectCreate(name,OBJ_TEXT,0,t,p);
   ObjectSetText(name,txt,9,"Arial",clr);
}

void DrawABCFromSeries(const int &bars[], const double &vals[], const datetime &time[], color clrLine, color clrLabel, string tag)
{
   int count=ArraySize(bars);
   if(count<3) return;

   int aBar=bars[count-3];
   int bBar=bars[count-2];
   int cBar=bars[count-1];

   double aVal=vals[count-3];
   double bVal=vals[count-2];
   double cVal=vals[count-1];

   DrawABCLine(tag+"_AB",time[aBar],aVal,time[bBar],bVal,clrLine,2);
   DrawABCLine(tag+"_BC",time[bBar],bVal,time[cBar],cVal,clrLine,2);
   DrawABCLabel(tag+"_A",time[aBar],aVal,"A",clrLabel);
   DrawABCLabel(tag+"_B",time[bBar],bVal,"B",clrLabel);
   DrawABCLabel(tag+"_C",time[cBar],cVal,"C",clrLabel);
}

int OnInit()
{
   IndicatorShortName("Professional Structural Stochastic Divergence - Stage 2 (MT4)");

   SetIndexBuffer(0, PriceSwingHighBuffer);
   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, 1, clrDodgerBlue);
   SetIndexArrow(0, 233);

   SetIndexBuffer(1, PriceSwingLowBuffer);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 1, clrCrimson);
   SetIndexArrow(1, 234);

   SetIndexBuffer(2, StochSwingHighBuffer);
   SetIndexStyle(2, DRAW_ARROW, STYLE_SOLID, 1, clrLimeGreen);
   SetIndexArrow(2, 159);

   SetIndexBuffer(3, StochSwingLowBuffer);
   SetIndexStyle(3, DRAW_ARROW, STYLE_SOLID, 1, clrOrangeRed);
   SetIndexArrow(3, 159);

   SetIndexBuffer(4, StochMainBuffer);
   SetIndexStyle(4, DRAW_NONE);

   SetIndexBuffer(5, StochSignalBuffer);
   SetIndexStyle(5, DRAW_NONE);

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexEmptyValue(2, EMPTY_VALUE);
   SetIndexEmptyValue(3, EMPTY_VALUE);

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
   if(rates_total < MathMax(InpSlowEMA, InpATRPeriod) + 20)
      return(0);

   int priceBars[];
   double priceVals[];
   int stochBars[];
   double stochVals[];

   for(int i=0; i<rates_total; i++)
   {
      PriceSwingHighBuffer[i]=EMPTY_VALUE;
      PriceSwingLowBuffer[i]=EMPTY_VALUE;
      StochSwingHighBuffer[i]=EMPTY_VALUE;
      StochSwingLowBuffer[i]=EMPTY_VALUE;
      StochMainBuffer[i]=iStochastic(NULL,0,InpKPeriod,InpDPeriod,InpSlowing,MODE_SMA,0,MODE_MAIN,i);
      StochSignalBuffer[i]=iStochastic(NULL,0,InpKPeriod,InpDPeriod,InpSlowing,MODE_SMA,0,MODE_SIGNAL,i);
   }

   int start = rates_total - 2;
   int priceDir = 0;
   int priceExtremeBar = start;
   double priceLegStart = close[start];
   double priceExtreme = close[start];

   int stochDir = 0;
   int stochExtremeBar = start;
   double stochLegStart = StochMainBuffer[start];
   double stochExtreme = StochMainBuffer[start];

   for(int i=start; i>=1; i--)
   {
      double atr = iATR(NULL,0,InpATRPeriod,i);
      if(atr <= 0.0)
         continue;

      double atrAvg = 0.0;
      int n;
      for(n=0; n<10 && i+n<rates_total; n++) atrAvg += iATR(NULL,0,InpATRPeriod,i+n);
      if(n>0) atrAvg /= n;

      bool compressed = (atrAvg>0.0 && atr < atrAvg*InpCompressionFactor);
      double emaFast = iMA(NULL,0,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,i);
      double emaSlow = iMA(NULL,0,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,i);
      double emaFastPrev = iMA(NULL,0,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,i+1);
      bool emaQualified = (MathAbs(emaFast-emaSlow) >= atr*InpEMASepATRMult || MathAbs(emaFast-emaFastPrev) >= atr*InpEMASlopeATRMult);

      if(priceDir==0)
      {
         priceLegStart = close[i+1];
         priceExtreme = close[i+1];
         priceExtremeBar = i+1;
         if(!compressed && emaQualified)
         {
            if(close[i]-priceLegStart >= atr*InpImpulseATRMult) { priceDir = 1; priceExtreme = high[i]; priceExtremeBar = i; }
            else if(priceLegStart-close[i] >= atr*InpImpulseATRMult) { priceDir = -1; priceExtreme = low[i]; priceExtremeBar = i; }
         }
      }
      else if(priceDir==1)
      {
         if(high[i] > priceExtreme) { priceExtreme = high[i]; priceExtremeBar = i; }
         if(priceExtreme-low[i] >= atr*InpRetraceATRMult)
         {
            PriceSwingHighBuffer[priceExtremeBar] = high[priceExtremeBar] + atr*0.15;
            int pn=ArraySize(priceBars); ArrayResize(priceBars,pn+1); ArrayResize(priceVals,pn+1);
            priceBars[pn]=priceExtremeBar; priceVals[pn]=high[priceExtremeBar];
            priceDir = -1; priceLegStart = priceExtreme; priceExtreme = low[i]; priceExtremeBar = i;
         }
      }
      else
      {
         if(low[i] < priceExtreme) { priceExtreme = low[i]; priceExtremeBar = i; }
         if(high[i]-priceExtreme >= atr*InpRetraceATRMult)
         {
            PriceSwingLowBuffer[priceExtremeBar] = low[priceExtremeBar] - atr*0.15;
            int pn2=ArraySize(priceBars); ArrayResize(priceBars,pn2+1); ArrayResize(priceVals,pn2+1);
            priceBars[pn2]=priceExtremeBar; priceVals[pn2]=low[priceExtremeBar];
            priceDir = 1; priceLegStart = priceExtreme; priceExtreme = high[i]; priceExtremeBar = i;
         }
      }

      double sv = StochMainBuffer[i];
      double svPrev = StochMainBuffer[i+1];

      if(stochDir==0)
      {
         stochLegStart = svPrev; stochExtreme = svPrev; stochExtremeBar = i+1;
         if(sv-stochLegStart >= InpStochImpulse) { stochDir=1; stochExtreme=sv; stochExtremeBar=i; }
         else if(stochLegStart-sv >= InpStochImpulse) { stochDir=-1; stochExtreme=sv; stochExtremeBar=i; }
      }
      else if(stochDir==1)
      {
         if(sv>stochExtreme) { stochExtreme=sv; stochExtremeBar=i; }
         if(stochExtreme-sv >= InpStochRetrace)
         {
            StochSwingHighBuffer[stochExtremeBar]=stochExtreme;
            int sn=ArraySize(stochBars); ArrayResize(stochBars,sn+1); ArrayResize(stochVals,sn+1);
            stochBars[sn]=stochExtremeBar; stochVals[sn]=stochExtreme;
            stochDir=-1; stochLegStart=stochExtreme; stochExtreme=sv; stochExtremeBar=i;
         }
      }
      else
      {
         if(sv<stochExtreme) { stochExtreme=sv; stochExtremeBar=i; }
         if(sv-stochExtreme >= InpStochRetrace)
         {
            StochSwingLowBuffer[stochExtremeBar]=stochExtreme;
            int sn2=ArraySize(stochBars); ArrayResize(stochBars,sn2+1); ArrayResize(stochVals,sn2+1);
            stochBars[sn2]=stochExtremeBar; stochVals[sn2]=stochExtreme;
            stochDir=1; stochLegStart=stochExtreme; stochExtreme=sv; stochExtremeBar=i;
         }
      }
   }

   ClearABCObjects();
   if(ArraySize(priceBars)>=3 && ArraySize(stochBars)>=3)
   {
      int pc=ArraySize(priceBars);
      int sc=ArraySize(stochBars);
      int dp=MathAbs(priceBars[pc-1]-stochBars[sc-1]);
      int db=MathAbs(priceBars[pc-2]-stochBars[sc-2]);
      int da=MathAbs(priceBars[pc-3]-stochBars[sc-3]);
      if(dp<=InpABCAlignmentBars && db<=InpABCAlignmentBars && da<=InpABCAlignmentBars)
      {
         DrawABCFromSeries(priceBars,priceVals,time,clrDeepSkyBlue,clrWhite,"PRICE");
         DrawABCFromSeries(stochBars,stochVals,time,clrGold,clrGold,"STOCH");
      }
   }

   return(rates_total);
}
