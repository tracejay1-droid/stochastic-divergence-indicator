#property strict
#property indicator_chart_window
#property indicator_plots 6
#property indicator_buffers 9

#property indicator_type1 DRAW_ARROW
#property indicator_color1 DodgerBlue
#property indicator_label1 "Price Structural Swing High"

#property indicator_type2 DRAW_ARROW
#property indicator_color2 Crimson
#property indicator_label2 "Price Structural Swing Low"

#property indicator_type3 DRAW_ARROW
#property indicator_color3 LimeGreen
#property indicator_label3 "Stoch Structural Swing High"

#property indicator_type4 DRAW_ARROW
#property indicator_color4 OrangeRed
#property indicator_label4 "Stoch Structural Swing Low"

#property indicator_type5 DRAW_NONE
#property indicator_label5 "Stoch Main"

#property indicator_type6 DRAW_NONE
#property indicator_label6 "Stoch Signal"

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

double PriceSwingHighBuffer[];
double PriceSwingLowBuffer[];
double StochSwingHighBuffer[];
double StochSwingLowBuffer[];
double StochMainBuffer[];
double StochSignalBuffer[];
double ATRBuffer[];
double EMAFastBuffer[];
double EMASlowBuffer[];

int atrHandle=INVALID_HANDLE;
int emaFastHandle=INVALID_HANDLE;
int emaSlowHandle=INVALID_HANDLE;
int stochHandle=INVALID_HANDLE;
string PREFIX="SSD_STAGE2_MT5_";

void ClearABCObjects()
{
   string ids[] = {"PRICE_AB","PRICE_BC","STOCH_AB","STOCH_BC","PRICE_A","PRICE_B","PRICE_C","STOCH_A","STOCH_B","STOCH_C"};
   for(int i=0;i<ArraySize(ids);i++) ObjectDelete(0,PREFIX+ids[i]);
}

void DrawABCLine(string id,datetime t1,double p1,datetime t2,double p2,color clr,int width)
{
   string name=PREFIX+id;
   ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
}

void DrawABCLabel(string id,datetime t,double p,string txt,color clr)
{
   string name=PREFIX+id;
   ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_TEXT,0,t,p);
   ObjectSetString(0,name,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
}

void DrawABCFromSeries(const int &bars[], const double &vals[], const datetime &time[], color clrLine, color clrLabel, string tag)
{
   int count=ArraySize(bars);
   if(count<3) return;

   int aBar=bars[count-3], bBar=bars[count-2], cBar=bars[count-1];
   double aVal=vals[count-3], bVal=vals[count-2], cVal=vals[count-1];

   DrawABCLine(tag+"_AB",time[aBar],aVal,time[bBar],bVal,clrLine,2);
   DrawABCLine(tag+"_BC",time[bBar],bVal,time[cBar],cVal,clrLine,2);
   DrawABCLabel(tag+"_A",time[aBar],aVal,"A",clrLabel);
   DrawABCLabel(tag+"_B",time[bBar],bVal,"B",clrLabel);
   DrawABCLabel(tag+"_C",time[cBar],cVal,"C",clrLabel);
}

int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME,"Professional Structural Stochastic Divergence - Stage 2 (MT5)");

   SetIndexBuffer(0,PriceSwingHighBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,PriceSwingLowBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,StochSwingHighBuffer,INDICATOR_DATA);
   SetIndexBuffer(3,StochSwingLowBuffer,INDICATOR_DATA);
   SetIndexBuffer(4,StochMainBuffer,INDICATOR_DATA);
   SetIndexBuffer(5,StochSignalBuffer,INDICATOR_DATA);
   SetIndexBuffer(6,ATRBuffer,INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,EMAFastBuffer,INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,EMASlowBuffer,INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0,PLOT_ARROW,233);
   PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetInteger(2,PLOT_ARROW,159);
   PlotIndexSetInteger(3,PLOT_ARROW,159);

   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(2,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(3,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   ArraySetAsSeries(PriceSwingHighBuffer,true);
   ArraySetAsSeries(PriceSwingLowBuffer,true);
   ArraySetAsSeries(StochSwingHighBuffer,true);
   ArraySetAsSeries(StochSwingLowBuffer,true);
   ArraySetAsSeries(StochMainBuffer,true);
   ArraySetAsSeries(StochSignalBuffer,true);
   ArraySetAsSeries(ATRBuffer,true);
   ArraySetAsSeries(EMAFastBuffer,true);
   ArraySetAsSeries(EMASlowBuffer,true);

   atrHandle=iATR(_Symbol,_Period,InpATRPeriod);
   emaFastHandle=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   emaSlowHandle=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   stochHandle=iStochastic(_Symbol,_Period,InpKPeriod,InpDPeriod,InpSlowing,MODE_SMA,STO_LOWHIGH);
   if(atrHandle==INVALID_HANDLE || emaFastHandle==INVALID_HANDLE || emaSlowHandle==INVALID_HANDLE || stochHandle==INVALID_HANDLE) return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(emaFastHandle!=INVALID_HANDLE) IndicatorRelease(emaFastHandle);
   if(emaSlowHandle!=INVALID_HANDLE) IndicatorRelease(emaSlowHandle);
   if(stochHandle!=INVALID_HANDLE) IndicatorRelease(stochHandle);
   ClearABCObjects();
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
   if(rates_total < MathMax(InpSlowEMA,InpATRPeriod)+20) return(0);
   if(CopyBuffer(atrHandle,0,0,rates_total,ATRBuffer)<=0) return(prev_calculated);
   if(CopyBuffer(emaFastHandle,0,0,rates_total,EMAFastBuffer)<=0) return(prev_calculated);
   if(CopyBuffer(emaSlowHandle,0,0,rates_total,EMASlowBuffer)<=0) return(prev_calculated);
   if(CopyBuffer(stochHandle,0,0,rates_total,StochMainBuffer)<=0) return(prev_calculated);
   if(CopyBuffer(stochHandle,1,0,rates_total,StochSignalBuffer)<=0) return(prev_calculated);

   int priceBars[]; double priceVals[];
   int stochBars[]; double stochVals[];

   for(int i=0;i<rates_total;i++)
   {
      PriceSwingHighBuffer[i]=EMPTY_VALUE;
      PriceSwingLowBuffer[i]=EMPTY_VALUE;
      StochSwingHighBuffer[i]=EMPTY_VALUE;
      StochSwingLowBuffer[i]=EMPTY_VALUE;
   }

   int start=rates_total-2;
   int priceDir=0, priceExtremeBar=start;
   double priceExtreme=close[start], priceLegStart=close[start];
   int stochDir=0, stochExtremeBar=start;
   double stochExtreme=StochMainBuffer[start], stochLegStart=StochMainBuffer[start];

   for(int i=start;i>=1;i--)
   {
      double atr=ATRBuffer[i];
      if(atr<=0.0) continue;

      double atrSum=0.0; int count=0;
      for(int n=0;n<10 && (i+n)<rates_total;n++){ atrSum+=ATRBuffer[i+n]; count++; }
      double atrAvg=(count>0?atrSum/count:atr);
      bool compressed=(atrAvg>0.0 && atr<atrAvg*InpCompressionFactor);
      double emaFast=EMAFastBuffer[i], emaSlow=EMASlowBuffer[i], emaFastPrev=EMAFastBuffer[i+1];
      bool emaQualified=(MathAbs(emaFast-emaSlow)>=atr*InpEMASepATRMult || MathAbs(emaFast-emaFastPrev)>=atr*InpEMASlopeATRMult);

      if(priceDir==0)
      {
         priceLegStart=close[i+1]; priceExtreme=close[i+1]; priceExtremeBar=i+1;
         if(!compressed && emaQualified)
         {
            if(close[i]-priceLegStart>=atr*InpImpulseATRMult){ priceDir=1; priceExtreme=high[i]; priceExtremeBar=i; }
            else if(priceLegStart-close[i]>=atr*InpImpulseATRMult){ priceDir=-1; priceExtreme=low[i]; priceExtremeBar=i; }
         }
      }
      else if(priceDir==1)
      {
         if(high[i]>priceExtreme){ priceExtreme=high[i]; priceExtremeBar=i; }
         if(priceExtreme-low[i]>=atr*InpRetraceATRMult)
         {
            PriceSwingHighBuffer[priceExtremeBar]=high[priceExtremeBar]+atr*0.15;
            int pn=ArraySize(priceBars); ArrayResize(priceBars,pn+1); ArrayResize(priceVals,pn+1);
            priceBars[pn]=priceExtremeBar; priceVals[pn]=high[priceExtremeBar];
            priceDir=-1; priceLegStart=priceExtreme; priceExtreme=low[i]; priceExtremeBar=i;
         }
      }
      else
      {
         if(low[i]<priceExtreme){ priceExtreme=low[i]; priceExtremeBar=i; }
         if(high[i]-priceExtreme>=atr*InpRetraceATRMult)
         {
            PriceSwingLowBuffer[priceExtremeBar]=low[priceExtremeBar]-atr*0.15;
            int pn2=ArraySize(priceBars); ArrayResize(priceBars,pn2+1); ArrayResize(priceVals,pn2+1);
            priceBars[pn2]=priceExtremeBar; priceVals[pn2]=low[priceExtremeBar];
            priceDir=1; priceLegStart=priceExtreme; priceExtreme=high[i]; priceExtremeBar=i;
         }
      }

      double sv=StochMainBuffer[i], svPrev=StochMainBuffer[i+1];
      if(stochDir==0)
      {
         stochLegStart=svPrev; stochExtreme=svPrev; stochExtremeBar=i+1;
         if(sv-stochLegStart>=InpStochImpulse){ stochDir=1; stochExtreme=sv; stochExtremeBar=i; }
         else if(stochLegStart-sv>=InpStochImpulse){ stochDir=-1; stochExtreme=sv; stochExtremeBar=i; }
      }
      else if(stochDir==1)
      {
         if(sv>stochExtreme){ stochExtreme=sv; stochExtremeBar=i; }
         if(stochExtreme-sv>=InpStochRetrace)
         {
            StochSwingHighBuffer[stochExtremeBar]=stochExtreme;
            int sn=ArraySize(stochBars); ArrayResize(stochBars,sn+1); ArrayResize(stochVals,sn+1);
            stochBars[sn]=stochExtremeBar; stochVals[sn]=stochExtreme;
            stochDir=-1; stochLegStart=stochExtreme; stochExtreme=sv; stochExtremeBar=i;
         }
      }
      else
      {
         if(sv<stochExtreme){ stochExtreme=sv; stochExtremeBar=i; }
         if(sv-stochExtreme>=InpStochRetrace)
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
      int pc=ArraySize(priceBars), sc=ArraySize(stochBars);
      int da=MathAbs(priceBars[pc-3]-stochBars[sc-3]);
      int db=MathAbs(priceBars[pc-2]-stochBars[sc-2]);
      int dc=MathAbs(priceBars[pc-1]-stochBars[sc-1]);
      if(da<=InpABCAlignmentBars && db<=InpABCAlignmentBars && dc<=InpABCAlignmentBars)
      {
         DrawABCFromSeries(priceBars,priceVals,time,clrDeepSkyBlue,clrWhite,"PRICE");
         DrawABCFromSeries(stochBars,stochVals,time,clrGold,clrGold,"STOCH");
      }
   }

   return(rates_total);
}
